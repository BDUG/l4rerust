use std::env;

fn main() {
    if env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() != "l4re" {
        return;
    }
    let mut build = cc::Build::new();
    build.file("ipc/syscall.c");
    if let Ok(include_dirs) = env::var("L4_INCLUDE_DIRS") {
        for dir in include_dirs.split_whitespace() {
            build.flag(dir);
        }
    }
    build.compile("l4rust_syscalls");
}
