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

After running `gmake setup` once to initialize the tree, invoking `gmake`
without arguments now builds the `systemd-image` target. This produces a
systemd-based boot image and serves as the primary build configuration. Other
gmake targets remain available—run them explicitly (for example,
`gmake bash-image` or `gmake examples`) when you need alternative outputs.

On a host with the necessary prerequisites installed, run:

**Linux:**
```bash
scripts/build.sh          # builds the systemd image natively
```

**Mac:**
```bash
CROSS_COMPILE=aarch64-linux-gnu- scripts/build.sh  # Supply the Linux-targeted prefix explicitly.
```

Pass `--clean` (or select “Clean out directory before build” in the interactive
menu) to remove previous build directories. By default the script reuses
existing directories for incremental builds; `--no-clean` enforces this reuse in
automation. Build artifacts are placed under `out/`.

When `dialog` is available the script shows interactive checklists covering the
external components (Bash, libcap, systemd, etc.) to build and the make target
to invoke, followed by a cleanup prompt. The make-target list is now limited to
the systemd image and defaults to that selection. Choose the desired entries or
pass `--no-menu` (and optionally `--components=foo,bar`) to skip the prompts in
automation. To invoke other make targets, call `gmake <target>` directly after
the script completes or run the desired target via `gmake` without using the
menu.

At the end of the run the script prints summary tables enumerating each
external component and make target as `success`, `skipped`, or `failed`. A
non-zero exit status is returned if any selected step fails so CI jobs can halt
before invoking later stages.

All bootable `.elf` outputs—and any generated `.uimage` files—found under
`obj/l4/*/images/` (including nested entry-point directories created from
`.imagebuilds`) are staged into `out/images/`. When multiple images share a
basename, the most recently built file wins so the latest
`bootstrap_hello_arm_virt.elf` remains available without manual intervention.

After building, boot the image on your host with:

```bash
scripts/runqemu.sh        # launches bootstrap_hello_arm_virt.elf or the newest .elf image
```

If you need a fresh rebuild, rerun the script with `--clean` to remove previous
outputs before starting.

## CMake build

The repository also exposes a CMake entry point at the repository root. Create
an out-of-source build directory and configure it with:

```bash
cmake -S . -B build
```

The configuration step accepts the usual `CMAKE_TOOLCHAIN_FILE` argument if you
maintain a bespoke toolchain description:

```bash
cmake -S . -B build \
  -DCMAKE_TOOLCHAIN_FILE=/path/to/toolchain.cmake
```

Alternatively, pass compilers directly on the command line. The cache variables
`CROSS_COMPILE_ARM`, `CROSS_COMPILE_ARM64`, `CROSS_COMPILE_MIPS32R2`,
`CROSS_COMPILE_MIPS32R6`, `CROSS_COMPILE_MIPS64R2`, and `CROSS_COMPILE_MIPS64R6`
mirror the existing environment variables used by the gmake flow, allowing
toolchain prefixes to be configured without exporting environment state:

```bash
cmake -S . -B build \
  -DL4RE_CORE_DIR=/path/to/l4re-core \
  -DCROSS_COMPILE_ARM=arm-linux-gnueabihf- \
  -DCROSS_COMPILE_ARM64=aarch64-linux-gnu-
```

After configuration, build the selected targets as usual:

```bash
cmake --build build
```

## Installing and consuming `libl4re-wrapper`

Run the standard install step to stage the static archive, CMake package files,
and headers into a prefix of your choice:

```bash
cmake --install build --prefix /opt/l4rerust
```

The archive and its optional import library are written to the prefix's
`lib/` directory, headers install under `include/l4/l4rust/`, and
`lib/pkgconfig/libl4re-wrapper.pc` advertises the same dependencies as the
original gmake build.

Rust build scripts can continue exporting `L4_INCLUDE_DIRS` by reusing the
pkg-config metadata:

```bash
export PKG_CONFIG_PATH=/opt/l4rerust/lib/pkgconfig:${PKG_CONFIG_PATH}
export L4_INCLUDE_DIRS="$(pkg-config --cflags-only-I libl4re-wrapper)"
```

Crates that use the [`pkg-config`](https://crates.io/crates/pkg-config)
helper can skip the environment variable entirely and simply query for the
wrapper library:

```rust
pkg_config::Config::new().probe("libl4re-wrapper")?;
```

Consumers that prefer CMake can locate the installed archive with the provided
package configuration:

```cmake
find_package(libl4re-wrapper CONFIG REQUIRED)
target_link_libraries(my-target PRIVATE l4rust::libl4re-wrapper)
```

### Staged capability and crypt libraries

`scripts/build.sh` cross-compiles libcap and libcrypt (via libxcrypt) for each
supported architecture. The staged headers, libraries, and pkg-config files are
written to `out/libcap/<arch>` and `out/libcrypt/<arch>` and can be installed
into other prefixes with `gmake -C pkg/libcap install ...` or
`gmake -C pkg/libcrypt install ...`.

## Further documents

### Building for ARM
Steps for building the project for ARM targets are documented in [docs/build.md](docs/build.md).

### Cross-compilation toolchains
Guidance on required cross-compilers and environment setup is in [docs/toolchains.md](docs/toolchains.md).

### macOS (Apple Silicon)
macOS-specific toolchain setup is covered in [docs/toolchains.md](docs/toolchains.md).

### Driver packaging workflow
See [docs/driver-packaging.md](docs/driver-packaging.md) for the end-to-end
packaging flow. The menu-based helper described there depends on the external
`dialog` utility, falling back to plain prompts when the binary is unavailable.
Details on packaging drivers for L4Re are provided in [docs/driver-packaging.md](docs/driver-packaging.md).

### Systemd integration
Learn how to integrate systemd into the build in [docs/systemd.md](docs/systemd.md).
