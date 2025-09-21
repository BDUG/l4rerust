# Build

The build system relies on the [`ham`](https://github.com/kernkonzept/ham)
tool to fetch L4Re manifests. The binary is expected at `ham/ham` relative to
the repository root before invoking any build commands. See the [Installing
ham](../README.md#installing-ham) section in the repository root for setup
instructions.

## Repository setup

Before running any of the build scripts, the L4Re snapshot must be configured.
The `scripts/setup.sh` helper now provides a unified, non-interactive entry point which
performs both the configuration and setup phases in a single call:

```bash
scripts/setup.sh --non-interactive
```

This generates the necessary configuration files and Makefiles using sensible
defaults. The traditional interactive invocation (`scripts/setup.sh config` followed by
`scripts/setup.sh setup` or `gmake setup`) remains available for manual configuration.

## Building for ARM

Use `scripts/build.sh` to build the project. By default the script reuses
previous build artifacts so incremental builds are faster. Pass `--clean` (or
select “Clean out directory before build” in the interactive menu) to remove old
artifacts before compilation, and use `--no-clean` to explicitly request reuse
in automation.

Built components and images are collected under the `out/` directory. Every
bootable `.elf` (and any generated `.uimage`) discovered under
`obj/l4/*/images/`—including nested entry-point directories produced by
`.imagebuilds`—is staged into `out/images/`, overwriting older copies when
duplicates share a basename. To boot an image on your host, run
`scripts/runqemu.sh`. The script automatically chooses a sensible default image
(preferring `out/images/bootstrap_hello_arm_virt.elf`) but accepts a path to
another image when provided.

The build scripts store version markers alongside cross-compiled binaries (for
example `out/bash/arm/VERSION`). When the version constants in `scripts/build.sh`
change, the updated marker causes the corresponding component to be rebuilt
automatically on the next run.

The build process first compiles the `l4re-libc` crate to provide a static
libc for the Rust components. The resulting library is made available through
the `LIBRARY_PATH` environment variable so that subsequent Rust crates link
against it automatically.

To rebuild manually outside of the script:

```
cargo build -p l4re-libc --release
export LIBRARY_PATH=$(pwd)/target/release:${LIBRARY_PATH}
gmake
```

Ensuring `LIBRARY_PATH` is set correctly allows the Rust crates to link against
the freshly built static libc.

