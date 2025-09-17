# L4ReRust

L4ReRust brings the Rust programming language to the L4 Runtime Environment (L4Re) microkernel.

The project aims to let developers system components in Rust with modern tooling, while taking over from Linux trunck the latest and greatest driver.

## Installing tool 'ham'

The build scripts rely on the [`ham`](https://github.com/kernkonzept/ham)
tool to synchronize L4Re manifests. The executable must reside at
`ham/ham` relative to the repository root.

Clone and build `ham` from source:

```bash
git clone https://github.com/kernkonzept/ham.git ham
(cd ham && gmake)
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

## Updating l4re-core

L4ReRust depends on a checkout of the upstream `l4re-core` repository. Run
`scripts/update_l4re_core.sh` to clone or refresh this source tree. The script
requires `git` and network access to fetch updates.

To pin `l4re-core` to a specific revision, pass the desired branch or commit as
an argument or via the `L4RE_CORE_REV` environment variable. If no revision is
specified, `origin/master` is used.

Examples:

```bash
scripts/update_l4re_core.sh my-feature-branch   # checkout a branch
L4RE_CORE_REV=abc123 scripts/update_l4re_core.sh  # checkout a commit
```

The build scripts invoke this step automatically, but you can call it manually
when developing locally to ensure `l4re-core` is up to date.

## Standard Build

On a host with the necessary prerequisites installed, run:

**Linux:**
```bash
scripts/build.sh          # builds natively
```

**Mac:**
```bash
CROSS_COMPILE=aarch64-linux-gnu- scripts/build.sh  # Override any aarch64-elf- default.
```

Pass `--clean` (the default) to force removal of previous build directories or
`--no-clean` to reuse them for incremental builds. Build artifacts are placed
under `out/`.

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
