use std::{env, fs};
use std::path::PathBuf;

fn main() {
    if env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() != "l4re" {
        let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
        fs::write(out_path.join("bindings.rs"), "// l4re stubs for non-L4Re targets\n")
            .expect("failed to write stub bindings");
        return;
    }
    let mut bindings = bindgen::Builder::default()
        .use_core()
        .ctypes_prefix("core::ffi")
        .rustified_enum(".*")
        .header("bindgen.h");

    let libc_include =
        PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("../l4re-libc/include");
    bindings = bindings.clang_arg(format!("-I{}", libc_include.display()));

    if let Ok(include_dirs) = ::std::env::var("L4_INCLUDE_DIRS") {
        for item in include_dirs.split(" ") {
            bindings = bindings.clang_arg(item);
        }
    }
    let bindings = bindings.generate().expect("Unable to generate bindings");
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
