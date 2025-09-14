# L4ReRust

L4ReRust brings the Rust programming language back to the L4 Runtime Environment (L4Re) microkernel.
The project aims to let developers build drivers and system components in Rust with modern tooling,
a containerized build environment, and workflows for packaging and deployment.

## Installing tool 'ham'

The build scripts rely on the [`ham`](https://github.com/kernkonzept/ham)
tool to synchronize L4Re manifests. The executable must reside at
`ham/ham` relative to the repository root.

Clone and build `ham` from source:

```bash
git clone https://github.com/kernkonzept/ham.git ham
(cd ham && make)
```

Or download a prebuilt binary:

```bash
mkdir -p ham
curl -L https://github.com/kernkonzept/ham/releases/latest/download/ham -o ham/ham
chmod +x ham/ham
```

Ensure the binary is executable and available on your `PATH` if you wish to
invoke it globally.

```bash
export PATH=ham/:$PATH
```

## Standard Build

On a host with the necessary prerequisites installed, run:

**Linux:**
```bash
scripts/build.sh          # builds natively
```

**Mac:**
```bash
CROSS_COMPILE=aarch64-elf- CROSS_COMPILE_ARM64=aarch64-elf- scripts/build.sh
```

Build artifacts are placed under `out/`. 

**Fallback**, to cross-compile inside a container, run:

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
## Further documents

### Building for ARM
Steps for building the project for ARM targets are documented in [docs/build.md](docs/build.md).

### Cross-compilation toolchains
Guidance on required cross-compilers and environment setup is in [docs/toolchains.md](docs/toolchains.md).

### macOS (Apple Silicon)
macOS-specific toolchain setup is covered in [docs/toolchains.md](docs/toolchains.md).

### Driver packaging workflow
Details on packaging drivers for L4Re are provided in [docs/driver-packaging.md](docs/driver-packaging.md).

### Systemd integration
Learn how to integrate systemd into the build in [docs/systemd.md](docs/systemd.md).
