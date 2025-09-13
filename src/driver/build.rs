use std::env;
use walkdir::WalkDir;

fn main() {
    let mut build = cc::Build::new();
    build
        .flag("-ffreestanding")
        .flag("-fno-builtin")
        .flag("-nostdlib");

    for entry in WalkDir::new("src") {
        let entry = entry.unwrap();
        if entry.file_type().is_file() {
            if let Some(ext) = entry.path().extension() {
                if ext == "c" {
                    build.file(entry.path());
                }
            }
        }
    }

    // Mirror CROSS_COMPILE setup from scripts/build_arm.sh
    if let Ok(prefix) = env::var("CROSS_COMPILE") {
        build.compiler(format!("{}gcc", prefix));
        build.archiver(format!("{}ar", prefix));
    }
    build.compile("driver");
}
