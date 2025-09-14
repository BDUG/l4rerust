# L4ReRust

L4ReRust brings the Rust programming language back to the L4 Runtime Environment (L4Re) microkernel.
The project aims to let developers build drivers and system components in Rust with modern tooling,
a containerized build environment, and workflows for packaging and deployment.

## Quick Start
1. Install toolchains and prerequisites: see [docs/toolchains.md](docs/toolchains.md).
2. Build the project or container: follow [docs/build.md](docs/build.md).
   For ARM targets, use the ARM section in that document.
3. Package drivers using [docs/driver-packaging.md](docs/driver-packaging.md).
4. Integrate systemd services as described in [docs/systemd.md](docs/systemd.md).

## Standard Build

On a host with the necessary prerequisites installed, run:

```bash
scripts/build.sh          # builds natively
```

Build artifacts are placed under `out/`. To cross-compile inside a container, run:

```bash
scripts/docker_build.sh   # cross-compiles and places artifacts in out/
```

After building, boot the image on your host with:

```bash
scripts/runqemu.sh        # launches the default image from out/images/
```

In case of issues with the Docker build container, run:

```bash
docker image rm l4rerust-builder
```

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
