# Build

The build system relies on the [`ham`](https://github.com/kernkonzept/ham)
tool to fetch L4Re manifests. The binary is expected at `ham/ham` relative to
the repository root before invoking any build commands. See the [Installing
ham](../README.md#installing-ham) section in the repository root for setup
instructions.

## Repository setup

Before running any of the build scripts, the L4Re snapshot must be configured.
The setup script now provides a unified, non-interactive entry point which
performs both the configuration and setup phases in a single call:

```bash
./setup --non-interactive
```

This generates the necessary configuration files and Makefiles using sensible
defaults. The traditional interactive invocation (`./setup config` followed by
`./setup setup` or `gmake setup`) remains available for manual configuration.

## Containerized build

If cross-compilers or required GNU utilities are not available on the host,
the project can be built inside a Docker container. Ensure
[Docker](https://www.docker.com/) is installed and run:

```bash
scripts/docker_build.sh
```

The script builds the image if needed and invokes `scripts/build.sh` inside the
container. It performs cross-compilation only and places resulting artifacts
under `out/`. All toolchains and GNU utilities are provided by the container,
so nothing else needs to be installed on the host.

For non-interactive Docker builds, the scripts look for an existing L4Re
configuration in `/workspace/.config` or `scripts/l4re.config`. If either file
is present, it is copied to `obj/.config` before running `setup`, allowing
developers to tailor the build by editing `scripts/l4re.config`.

To boot the built image on your host, run:

```bash
scripts/runqemu.sh
```

## Building for ARM

Use `scripts/build.sh` to build the project. By default, previous build
artifacts are removed before compilation. Passing `--no-clean` skips this
cleanup.

Built components and images are collected under the `out/` directory. To boot
an image on your host, run `scripts/runqemu.sh` and optionally pass the path to
the desired image in `out/images/`.

The build process first compiles the `l4re-libc` crate to provide a static
libc for the Rust components. The resulting library is made available through
the `LIBRARY_PATH` environment variable so that subsequent Rust crates link
against it automatically.

To rebuild manually outside of the script:

```
cd src/l4rust
cargo build -p l4re-libc --release
export LIBRARY_PATH=$(pwd)/target/release:${LIBRARY_PATH}
cd -
gmake
```

Ensuring `LIBRARY_PATH` is set correctly allows the Rust crates to link against
the freshly built static libc.

