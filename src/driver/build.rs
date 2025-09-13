use std::env;

fn main() {
    let mut build = cc::Build::new();
    build
        .file("driver.c")
        .flag("-ffreestanding")
        .flag("-fno-builtin")
        .flag("-nostdlib");
    // Mirror CROSS_COMPILE setup from scripts/build_arm.sh
    if let Ok(prefix) = env::var("CROSS_COMPILE") {
        build.compiler(format!("{}gcc", prefix));
        build.archiver(format!("{}ar", prefix));
    }
    build.compile("driver");
}
