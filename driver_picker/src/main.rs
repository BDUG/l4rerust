use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use clap::Parser;
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
                let subsystem = rel.components().next().unwrap().as_os_str().to_string_lossy().to_string();
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
    // Best-effort: invoke `make M=<dir> depend` to generate .cmd files
    let status = std::process::Command::new("make")
        .arg("-C")
        .arg(linux_src)
        .arg(format!("M={}", driver_dir.display()))
        .arg("depend")
        .status()
        .context("running make depend")?;
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

    let subsystems: Vec<_> = map.keys().cloned().collect();
    let subsystem_choice = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("Select subsystem")
        .items(&subsystems)
        .default(0)
        .interact()?;
    let subsystem = &subsystems[subsystem_choice];
    let drivers = map.get(subsystem).unwrap();
    let driver_symbols: Vec<_> = drivers.iter().map(|d| d.symbol.clone()).collect();
    let driver_choice = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("Select driver")
        .items(&driver_symbols)
        .default(0)
        .interact()?;
    let driver = &drivers[driver_choice];

    let tmp = tempdir()?;
    let dst = tmp.path();
    let mut files = Vec::new();
    copy_tree(&driver.dir, dst, &mut files)?;
    fs::copy(&driver.kconfig, dst.join("Kconfig"))?;

    let headers = run_make_depend(&args.linux_src, &driver.dir)?;
    for h in &headers {
        if let Ok(rel) = h.strip_prefix(&args.linux_src) {
            let dest = dst.join(rel);
            if let Some(parent) = dest.parent() { fs::create_dir_all(parent)?; }
            fs::copy(h, &dest).ok();
            files.push(dest);
        }
    }

    let manifest = Manifest {
        driver: driver.symbol.clone(),
        subsystem: subsystem.clone(),
        files: files.clone(),
        headers: headers
            .iter()
            .map(|h| h.strip_prefix(&args.linux_src).unwrap().to_path_buf())
            .collect(),
        kconfig: PathBuf::from("Kconfig"),
        cflags: vec![],
    };
    let manifest_path = dst.join("driver.yaml");
    fs::write(&manifest_path, serde_yaml::to_string(&manifest)?)?;
    println!("Workspace: {}", dst.display());
    println!("Manifest written to {}", manifest_path.display());

    Ok(())
}
