use std::{
    collections::BTreeSet,
    env, fs,
    path::{Path, PathBuf},
};

const MUSL_LIBS: &[&str] = &["c"];
const L4RE_CORE_REQUIRED_LIBS: &[&str] = &["l4re_c", "l4re_c-util"];
const L4RE_PTHREAD_LIB_CANDIDATES: &[&str] = &["pthread-l4", "pthread", "l4pthread", "c_pthread"];

fn main() {
    if env::var_os("CARGO_FEATURE_SYSCALL_FALLBACKS").is_some() {
        compile_syscall_wrappers();
    }

    configure_l4re_core_linkage();
    configure_musl_linkage();
}

fn compile_syscall_wrappers() {
    let mut build = cc::Build::new();
    build.include("include");
    build.file("src/epoll.c");
    build.file("src/eventfd.c");
    build.file("src/signalfd.c");
    build.file("src/timerfd.c");
    build.file("src/inotify.c");
    build.compile("l4re_libc_c");
}

fn configure_l4re_core_linkage() {
    println!("cargo:rerun-if-env-changed=L4RE_CORE_DIR");

    let manifest_dir =
        PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set"));
    let default_core_dir = manifest_dir
        .join("..")
        .join("..")
        .join("src")
        .join("l4re-core");
    let core_dir = env::var_os("L4RE_CORE_DIR")
        .map(PathBuf::from)
        .unwrap_or(default_core_dir);

    if !core_dir.exists() {
        println!(
            "cargo:warning=L4Re core directory '{}' does not exist; skipping core linkage",
            core_dir.display()
        );
        return;
    }

    let candidate_dirs = discover_l4re_library_dirs(&core_dir);
    if candidate_dirs.is_empty() {
        println!(
            "cargo:warning=Unable to locate any L4Re core library directories under '{}'",
            core_dir.display()
        );
        return;
    }

    let mut linked_dirs = Vec::new();
    for dir in candidate_dirs {
        if ensure_libraries_present(&dir, L4RE_CORE_REQUIRED_LIBS) {
            if !linked_dirs.iter().any(|d: &PathBuf| d == &dir) {
                println!("cargo:rustc-link-search=native={}", dir.display());
                linked_dirs.push(dir);
            }
        }
    }

    if linked_dirs.is_empty() {
        println!(
            "cargo:warning=Failed to locate required L4Re core libraries ({}); builds may fail",
            L4RE_CORE_REQUIRED_LIBS.join(", ")
        );
        return;
    }

    for lib in L4RE_CORE_REQUIRED_LIBS {
        println!("cargo:rustc-link-lib={}", lib);
    }

    if let Some(pthread_lib) = linked_dirs
        .iter()
        .find_map(|dir| find_existing_library(dir, L4RE_PTHREAD_LIB_CANDIDATES))
    {
        println!("cargo:rustc-link-lib={}", pthread_lib);
    } else if !link_system_pthread_fallback() {
        println!(
            "cargo:warning=Failed to locate an L4Re pthread library (candidates: {}); builds may fail",
            L4RE_PTHREAD_LIB_CANDIDATES.join(", ")
        );
    }
}

fn configure_musl_linkage() {
    let Some(prefix) = resolve_musl_prefix() else {
        return;
    };
    let lib_dir = prefix.join("lib");
    if !lib_dir.is_dir() {
        panic!(
            "musl prefix '{}' does not contain a 'lib' directory",
            prefix.display()
        );
    }

    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    for lib in MUSL_LIBS {
        println!("cargo:rustc-link-lib={}", lib);
    }
}

fn resolve_musl_prefix() -> Option<PathBuf> {
    let manifest_dir =
        PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set"));
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_else(|_| "unknown".to_string());
    let target_env = env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let require_musl = target_env == "musl" || target_os == "l4re";

    let mut env_candidates = Vec::new();
    let arch_upper = target_arch.to_uppercase();
    env_candidates.push(format!("L4RE_LIBC_MUSL_PREFIX_{}", arch_upper));
    match target_arch.as_str() {
        "aarch64" => env_candidates.push("L4RE_LIBC_MUSL_PREFIX_ARM64".to_string()),
        "arm" => env_candidates.push("L4RE_LIBC_MUSL_PREFIX_ARM".to_string()),
        "armv8r" => env_candidates.push("L4RE_LIBC_MUSL_PREFIX_ARM".to_string()),
        _ => {}
    }
    env_candidates.push("L4RE_LIBC_MUSL_PREFIX".to_string());

    for var in &env_candidates {
        println!("cargo:rerun-if-env-changed={}", var);
    }

    for var in env_candidates {
        if let Ok(value) = env::var(&var) {
            let path = Path::new(&value);
            if path.exists() {
                return Some(canonicalize(path));
            }
            panic!(
                "Environment variable '{}' points to missing musl prefix '{}'",
                var,
                path.display()
            );
        }
    }

    let stage_arch = match target_arch.as_str() {
        "aarch64" => "arm64",
        "arm" => "arm",
        "armv8r" => "arm",
        other => other,
    };

    let default_prefix = manifest_dir
        .join("..")
        .join("..")
        .join("out")
        .join("musl")
        .join(stage_arch);
    if default_prefix.exists() {
        if require_musl {
            return Some(canonicalize(&default_prefix));
        }
        return None;
    }

    if require_musl {
        panic!(
            "Unable to locate musl staging prefix for target arch '{}'. \
Set L4RE_LIBC_MUSL_PREFIX or L4RE_LIBC_MUSL_PREFIX_{} to the staged musl directory.",
            target_arch,
            arch_uppercase_fallback(&target_arch)
        );
    }

    None
}

fn canonicalize(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

fn arch_uppercase_fallback(target_arch: &str) -> String {
    match target_arch {
        "aarch64" => "ARM64".to_string(),
        "armv8r" => "ARM".to_string(),
        other => other.to_uppercase(),
    }
}

fn discover_l4re_library_dirs(core_dir: &Path) -> Vec<PathBuf> {
    let mut dirs = BTreeSet::new();

    push_if_dir(&mut dirs, core_dir.to_path_buf());
    for suffix in [
        "lib",
        "lib32",
        "lib64",
        "lib/arm",
        "lib/aarch64",
        "lib/amd64",
        "lib/mips",
        "lib/mips32",
        "lib/mips64",
        "lib/ppc32",
        "lib/riscv",
        "lib/riscv64",
        "lib/x86",
    ] {
        push_if_dir(&mut dirs, core_dir.join(suffix));
    }

    if let Ok(entries) = fs::read_dir(core_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                push_if_dir(&mut dirs, path.join("lib"));
                if let Ok(subdirs) = fs::read_dir(path.join("lib")) {
                    for sub in subdirs.flatten() {
                        push_if_dir(&mut dirs, sub.path());
                    }
                }
            }
        }
    }

    if let Ok(entries) = fs::read_dir(core_dir.join("lib")) {
        for entry in entries.flatten() {
            push_if_dir(&mut dirs, entry.path());
        }
    }

    dirs.into_iter().collect()
}

fn push_if_dir(set: &mut BTreeSet<PathBuf>, path: PathBuf) {
    if path.is_dir() {
        set.insert(path);
    }
}

fn ensure_libraries_present(dir: &Path, libs: &[&str]) -> bool {
    libs.iter().all(|lib| library_exists(dir, lib))
}

fn library_exists(dir: &Path, lib: &str) -> bool {
    let base = format!("lib{}", lib);
    let static_path = dir.join(format!("{}.a", base));
    if file_non_empty(&static_path) {
        return true;
    }

    let shared_path = dir.join(format!("{}.so", base));
    if file_non_empty(&shared_path) {
        return true;
    }

    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let file_name = entry.file_name();
            if let Some(name) = file_name.to_str() {
                if name.starts_with(&format!("{}.so", base)) && file_non_empty(&entry.path()) {
                    return true;
                }
            }
        }
    }

    false
}

fn find_existing_library<'a>(dir: &Path, libs: &'a [&str]) -> Option<&'a str> {
    libs.iter().copied().find(|lib| library_exists(dir, lib))
}

fn file_non_empty(path: &Path) -> bool {
    path.metadata().map(|meta| meta.len() > 0).unwrap_or(false)
}

fn link_system_pthread_fallback() -> bool {
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os == "l4re" {
        return false;
    }

    println!("cargo:rustc-link-lib=pthread");
    println!(
        "cargo:warning=Falling back to linking against the system pthread library; set L4RE_CORE_DIR to use L4Re-provided pthread variants"
    );
    true
}
