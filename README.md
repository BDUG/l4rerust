# L4ReRust

L4ReRust brings the Rust programming language back to the L4 Runtime Environment (L4Re) microkernel.
The project aims to let developers build drivers and system components in Rust with modern tooling,
a containerized build environment, and workflows for packaging and deployment.

## Quick Start
1. Install toolchains and prerequisites: see [docs/toolchains.md](docs/toolchains.md).
2. Obtain the `ham` build tool: see [Installing ham](#installing-ham).
3. Configure the snapshot: run `./setup --non-interactive` to generate
   default configuration files. The script performs both the `config` and
   `setup` phases without prompting.
4. Build the project or container: follow [docs/build.md](docs/build.md).
   For ARM targets, use the ARM section in that document.
5. Package drivers using [docs/driver-packaging.md](docs/driver-packaging.md).
6. Integrate systemd services as described in [docs/systemd.md](docs/systemd.md).

## Installing ham

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

### Mounted workspace

To work with a persistent workspace inside the container, create a directory on
the host and mount it at `/workspace`:

```bash
mkdir -p /path/to/host-workspace
scripts/docker_run.sh --workspace /path/to/host-workspace
```

The script resolves the path to an absolute location and forwards any remaining
arguments to `docker run`. The equivalent manual invocation is:

```bash
docker run --rm -it -v /path/to/host-workspace:/workspace l4rerust-builder
```

Inside the container the repository will appear under `/workspace`, which can be
verified with:

```bash
ls /workspace
```

#### Automatic startup

To launch the container automatically, define a shell alias:

```bash
alias l4re='~/l4rerust/scripts/docker_run.sh --workspace ~/l4re-workspace'
```

Or create a user systemd service:

```ini
# ~/.config/systemd/user/l4rerust.service
[Unit]
Description=L4ReRust development container

[Service]
ExecStart=/path/to/repo/scripts/docker_run.sh --workspace /path/to/host-workspace

[Install]
WantedBy=default.target
```

Enable it with `systemctl --user enable --now l4rerust.service`.

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
