use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};
use clap::{Parser, ValueEnum};
use dialoguer::{theme::ColorfulTheme, Select};
use regex::Regex;
use serde::Serialize;
use tempfile::tempdir;
use walkdir::WalkDir;

/// Simple CLI to pick Linux drivers and extract their sources
#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Args {
    /// Path to the Linux kernel source tree
    #[arg(long, env = "LINUX_SRC")]
    linux_src: PathBuf,
    /// Print the driver catalog and exit
    #[arg(long, default_value_t = false)]
    list: bool,
    /// Optional subsystem filter for non-interactive selection
    #[arg(long)]
    subsystem: Option<String>,
    /// Select a driver without prompting
    #[arg(long)]
    driver: Option<String>,
    /// Output format for --list results
    #[arg(long, value_enum, default_value = "tsv", requires = "list")]
    format: CatalogFormat,
}

#[derive(Copy, Clone, Debug, ValueEnum)]
enum CatalogFormat {
    Tsv,
    Json,
}

#[derive(Debug, Clone, Serialize)]
struct Manifest {
    driver: String,
    subsystem: String,
    files: Vec<PathBuf>,
    headers: Vec<PathBuf>,
    kconfig: PathBuf,
    cflags: Vec<String>,
}

#[derive(Debug, Clone)]
struct DriverInfo {
    symbol: String,
    dir: PathBuf,
    kconfig: PathBuf,
}

fn collect_drivers(linux_src: &Path) -> Result<HashMap<String, Vec<DriverInfo>>> {
    let drivers_dir = linux_src.join("drivers");
    let mut map: HashMap<String, Vec<DriverInfo>> = HashMap::new();
    let re = Regex::new(r"^config\\s+(\\w+)")?;

    for entry in WalkDir::new(&drivers_dir) {
        let entry = entry?;
        if entry.file_type().is_file() && entry.file_name() == "Kconfig" {
            let content = fs::read_to_string(entry.path())?;
            for cap in re.captures_iter(&content) {
                let symbol = cap[1].to_string();
                let dir = entry.path().parent().unwrap().to_path_buf();
                let rel = dir.strip_prefix(&drivers_dir).unwrap();
                let subsystem = rel
                    .components()
                    .next()
                    .unwrap()
                    .as_os_str()
                    .to_string_lossy()
                    .to_string();
                map.entry(subsystem).or_default().push(DriverInfo {
                    symbol,
                    dir,
                    kconfig: entry.path().to_path_buf(),
                });
            }
        }
    }
    Ok(map)
}

fn emit_catalog(map: &HashMap<String, Vec<DriverInfo>>, format: CatalogFormat) -> Result<()> {
    let mut subsystems: Vec<&String> = map.keys().collect();
    subsystems.sort_unstable();
    match format {
        CatalogFormat::Tsv => {
            for subsystem in &subsystems {
                let mut drivers: Vec<&DriverInfo> = map.get(*subsystem).unwrap().iter().collect();
                drivers.sort_unstable_by(|a, b| a.symbol.cmp(&b.symbol));
                for driver in drivers {
                    println!("{}\t{}", subsystem, driver.symbol);
                }
            }
        }
        CatalogFormat::Json => {
            #[derive(Serialize)]
            struct CatalogEntry<'a> {
                subsystem: &'a str,
                driver: &'a str,
            }

            let mut entries = Vec::new();
            for subsystem in &subsystems {
                let mut drivers: Vec<&DriverInfo> = map.get(*subsystem).unwrap().iter().collect();
                drivers.sort_unstable_by(|a, b| a.symbol.cmp(&b.symbol));
                for driver in drivers {
                    entries.push(CatalogEntry {
                        subsystem: subsystem.as_str(),
                        driver: driver.symbol.as_str(),
                    });
                }
            }
            println!("{}", serde_json::to_string_pretty(&entries)?);
        }
    }
    Ok(())
}

fn resolve_driver<'a>(
    map: &'a HashMap<String, Vec<DriverInfo>>,
    subsystem: Option<&'a String>,
    driver: &str,
) -> Result<(&'a str, &'a DriverInfo)> {
    if let Some(subsystem_name) = subsystem {
        let drivers = map
            .get(subsystem_name)
            .with_context(|| format!("Subsystem '{}' not found", subsystem_name))?;
        let driver_info = drivers
            .iter()
            .find(|d| d.symbol == driver)
            .with_context(|| {
                format!(
                    "Driver '{}' not found in subsystem '{}'",
                    driver, subsystem_name
                )
            })?;
        return Ok((subsystem_name.as_str(), driver_info));
    }

    let mut matches: Vec<(&str, &DriverInfo)> = Vec::new();
    for (subsystem_name, drivers) in map.iter() {
        if let Some(driver_info) = drivers.iter().find(|d| d.symbol == driver) {
            matches.push((subsystem_name.as_str(), driver_info));
        }
    }

    match matches.len() {
        0 => bail!("Driver '{}' not found", driver),
        1 => Ok(matches.remove(0)),
        _ => bail!(
            "Driver '{}' exists in multiple subsystems, please specify --subsystem",
            driver
        ),
    }
}

fn extract_driver(linux_src: &Path, subsystem: &str, driver: &DriverInfo) -> Result<()> {
    let tmp = tempdir()?;
    let workspace = tmp.keep();
    let mut files = Vec::new();

    copy_tree(&driver.dir, &workspace, &mut files)?;
    fs::copy(&driver.kconfig, workspace.join("Kconfig"))?;

    let headers = run_make_depend(linux_src, &driver.dir)?;
    for h in &headers {
        if let Ok(rel) = h.strip_prefix(linux_src) {
            let dest = workspace.join(rel);
            if let Some(parent) = dest.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(h, &dest).ok();
            files.push(dest);
        }
    }

    let manifest = Manifest {
        driver: driver.symbol.clone(),
        subsystem: subsystem.to_string(),
        files: files.clone(),
        headers: headers
            .iter()
            .map(|h| h.strip_prefix(linux_src).unwrap().to_path_buf())
            .collect(),
        kconfig: PathBuf::from("Kconfig"),
        cflags: vec![],
    };
    let manifest_path = workspace.join("driver.yaml");
    fs::write(&manifest_path, serde_yaml::to_string(&manifest)?)?;
    println!("Workspace: {}", workspace.display());
    println!("Manifest written to {}", manifest_path.display());

    Ok(())
}

fn copy_tree(src: &Path, dst: &Path, files: &mut Vec<PathBuf>) -> Result<()> {
    for entry in WalkDir::new(src) {
        let entry = entry?;
        let rel = entry.path().strip_prefix(src)?;
        let dest_path = dst.join(rel);
        if entry.file_type().is_dir() {
            fs::create_dir_all(&dest_path)?;
        } else if entry.file_type().is_file() {
            fs::copy(entry.path(), &dest_path)?;
            files.push(dest_path.clone());
        }
    }
    Ok(())
}

fn run_make_depend(linux_src: &Path, driver_dir: &Path) -> Result<Vec<PathBuf>> {
    // Best-effort: invoke `gmake M=<dir> depend` to generate .cmd files
    let status = std::process::Command::new("gmake")
        .arg("-C")
        .arg(linux_src)
        .arg(format!("M={}", driver_dir.display()))
        .arg("depend")
        .status()
        .context("running gmake depend")?;
    if !status.success() {
        return Ok(vec![]); // ignore failure
    }
    let mut headers = Vec::new();
    for entry in WalkDir::new(driver_dir) {
        let entry = entry?;
        if entry.file_type().is_file() {
            if let Some(ext) = entry.path().extension() {
                if ext == "cmd" {
                    let out = std::process::Command::new(linux_src.join("scripts/basic/fixdep"))
                        .arg(entry.path())
                        .output();
                    if let Ok(output) = out {
                        let text = String::from_utf8_lossy(&output.stdout);
                        for line in text.lines() {
                            if line.starts_with(" ") {
                                let path = line.trim();
                                let p = linux_src.join(path);
                                headers.push(p);
                            }
                        }
                    }
                }
            }
        }
    }
    Ok(headers)
}

fn main() -> Result<()> {
    let args = Args::parse();
    let map = collect_drivers(&args.linux_src)?;

    if args.list {
        emit_catalog(&map, args.format)?;
        return Ok(());
    }

    if let Some(driver) = &args.driver {
        let (subsystem, driver_info) = resolve_driver(&map, args.subsystem.as_ref(), driver)?;
        return extract_driver(&args.linux_src, subsystem, driver_info);
    }

    let mut subsystems: Vec<&String> = map.keys().collect();
    subsystems.sort_unstable();
    let subsystem_labels: Vec<_> = subsystems.iter().map(|s| s.as_str()).collect();
    let subsystem_choice = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("Select subsystem")
        .items(&subsystem_labels)
        .default(0)
        .interact()?;
    let subsystem = subsystems[subsystem_choice];
    let mut drivers: Vec<&DriverInfo> = map.get(subsystem).unwrap().iter().collect();
    drivers.sort_unstable_by(|a, b| a.symbol.cmp(&b.symbol));
    let driver_symbols: Vec<_> = drivers.iter().map(|d| d.symbol.as_str()).collect();
    let driver_choice = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("Select driver")
        .items(&driver_symbols)
        .default(0)
        .interact()?;
    let driver = drivers[driver_choice];

    extract_driver(&args.linux_src, subsystem.as_str(), driver)
}
