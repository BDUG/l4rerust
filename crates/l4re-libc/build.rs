use std::{
    env, fs,
    path::{Path, PathBuf},
};

const MUSL_LIBS: &[&str] = &["c", "pthread", "dl", "m", "rt", "resolv"];

fn main() {
    if env::var_os("CARGO_FEATURE_SYSCALL_FALLBACKS").is_some() {
        compile_syscall_wrappers();
    }

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
