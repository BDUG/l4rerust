use std::env;
use walkdir::WalkDir;

fn main() {
    let mut build = cc::Build::new();
    build
        .cpp(true)
        .flag("-ffreestanding")
        .flag("-fno-builtin")
        .flag("-nostdlib");

    // Ensure the top-level driver.cpp is compiled
    build.file("driver.cpp");

    for entry in WalkDir::new("src") {
        let entry = entry.unwrap();
        if entry.file_type().is_file() {
            if let Some(ext) = entry.path().extension() {
                if ext == "c" || ext == "cpp" {
                    build.file(entry.path());
                }
            }
        }
    }

    // Mirror CROSS_COMPILE setup from scripts/build.sh
    if let Ok(prefix) = env::var("CROSS_COMPILE") {
        build.compiler(format!("{}g++", prefix));
        build.archiver(format!("{}ar", prefix));
    }
    build.compile("driver");
}
