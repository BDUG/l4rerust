This project re-introduces Rust for the L4Re microkernel.

Starting point was the work of the project [rustl4re](https://github.com/humenda/rustl4re).

## Containerized build

Instructions for building inside a Docker container are available in [docs/build.md](docs/build.md).

## Building for ARM

Steps for building the project for ARM targets are documented in [docs/build.md](docs/build.md).

### Cross-compilation toolchains

Guidance on required cross-compilers and environment setup is in [docs/toolchains.md](docs/toolchains.md).

### macOS (Apple Silicon)

macOS-specific toolchain setup is covered in [docs/toolchains.md](docs/toolchains.md).

## Driver packaging workflow

Details on packaging drivers for L4Re are provided in [docs/driver-packaging.md](docs/driver-packaging.md).

## Systemd integration

Learn how to integrate systemd into the build in [docs/systemd.md](docs/systemd.md).
