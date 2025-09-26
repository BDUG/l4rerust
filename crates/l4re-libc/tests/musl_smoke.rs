use std::{
    env,
    ffi::CString,
    path::{Path, PathBuf},
};

fn musl_prefix_available() -> bool {
    let arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_else(|_| env::consts::ARCH.to_string());

    let mut env_candidates = Vec::new();
    env_candidates.push(format!("L4RE_LIBC_MUSL_PREFIX_{}", arch.to_uppercase()));
    match arch.as_str() {
        "aarch64" => env_candidates.push("L4RE_LIBC_MUSL_PREFIX_ARM64".to_string()),
        "arm" | "armv8r" => env_candidates.push("L4RE_LIBC_MUSL_PREFIX_ARM".to_string()),
        _ => {}
    }
    env_candidates.push("L4RE_LIBC_MUSL_PREFIX".to_string());

    for var in env_candidates {
        if let Ok(value) = env::var(&var) {
            if Path::new(&value).exists() {
                return true;
            }
        }
    }

    let stage_arch = match arch.as_str() {
        "aarch64" => "arm64",
        "arm" | "armv8r" => "arm",
        other => other,
    };

    let default_prefix = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("out")
        .join("musl")
        .join(stage_arch);
    default_prefix.exists()
}

#[test]
fn musl_libc_available() {
    if !musl_prefix_available() {
        eprintln!("skipping musl smoke test; musl staging prefix not found");
        return;
    }

    unsafe {
        let handle = libc::dlopen(std::ptr::null(), libc::RTLD_NOW);
        assert!(
            !handle.is_null(),
            "dlopen returned null handle for musl libc"
        );

        let symbol = CString::new("eventfd").unwrap();
        let ptr = libc::dlsym(handle, symbol.as_ptr());
        assert!(
            !ptr.is_null(),
            "dlsym failed to locate eventfd symbol via staged musl libc"
        );

        let symbol = CString::new("nanosleep").unwrap();
        let ptr = libc::dlsym(handle, symbol.as_ptr());
        assert!(
            !ptr.is_null(),
            "dlsym failed to locate nanosleep symbol via staged musl libc"
        );
        libc::dlclose(handle);
    }
}
