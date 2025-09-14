This project re-introduces Rust for the L4Re microkernel.

Starting point was the work of the project [rustl4re](https://github.com/humenda/rustl4re).

## Building for ARM

Use `scripts/build.sh` to build the project. By default, previous build
artifacts are removed before compilation. Passing `--no-clean` skips this
cleanup.

The script also accepts a `--test` flag which performs a brief QEMU boot using
the generated image `obj/l4/arm64/images/bootstrap_hello_arm_virt.elf`. The
script aborts if the QEMU run fails, providing a quick smoke test of the
build.

Built components and images are collected under the `out/` directory.

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
make
```

Ensuring `LIBRARY_PATH` is set correctly allows the Rust crates to link against
the freshly built static libc.

### Cross-compilation toolchains

Both the `setup` script and `scripts/build.sh` look for compiler prefixes
via the `CROSS_COMPILE_ARM` and `CROSS_COMPILE_ARM64` environment variables.
 Typical prefixes include `arm-linux-gnueabihf-` and `aarch64-linux-gnu-` on
 Linux hosts, or Homebrew's `arm-linux-gnueabihf-` and `aarch64-none-linux-gnu-` on macOS.
When these variables are unset, the scripts attempt to choose sensible defaults
based on `uname`.

### macOS (Apple Silicon)

On Apple Silicon hosts, Homebrew provides the required build tools and cross
compilers:

```bash
brew install qemu e2fsprogs coreutils meson ninja pkg-config
brew install arm-linux-gnueabihf-gcc aarch64-none-linux-gnu-gcc
```

Ensure the Homebrew prefixes are in your `PATH` and define the compiler
prefixes expected by the build scripts:

```bash
export PATH="$(brew --prefix e2fsprogs)/bin:$(brew --prefix arm-linux-gnueabihf-gcc)/bin:$(brew --prefix aarch64-none-linux-gnu-gcc)/bin:$PATH"
export CROSS_COMPILE_ARM=arm-linux-gnueabihf-
export CROSS_COMPILE_ARM64=aarch64-none-linux-gnu-
```

macOS does not ship GNU `timeout`; the `coreutils` formula installs it as
`gtimeout`. Either invoke `gtimeout` directly or alias it:

```bash
alias timeout=gtimeout
```

With the environment set up, a smoke test of the build can be run with:

```bash
CROSS_COMPILE_ARM=arm-linux-gnueabihf- \
CROSS_COMPILE_ARM64=aarch64-none-linux-gnu- \
scripts/build.sh --test
```

Some tools, such as `mke2fs` from `e2fsprogs`, live outside Homebrew's default
`bin` prefix; the `PATH` example above includes these locations.

## Driver packaging workflow

The `tools/l4re-driver-wrap` helper bundles driver selection, build scaffolding
generation, compilation of the virtio-enabled server, and L4Re packaging into a
single command. It produces a package under `src/pkg/<driver>/` that can be
consumed by the L4Re build system.

### Basic usage

```
tools/l4re-driver-wrap --linux-src /path/to/linux
```

The script launches an interactive selector to choose a driver from the Linux
source tree. After extraction, the driver is wrapped and a package directory is
created.

### Using a configuration file

Re-running the workflow for a different driver can be automated via a simple
configuration file:

```
cat >driver.conf <<EOF
LINUX_SRC=/home/user/linux
DRIVER=e1000
EOF

tools/l4re-driver-wrap --config driver.conf
```

The `DRIVER` variable controls the package name. If omitted, the name from the
generated manifest is used.

### Troubleshooting

* Ensure the `driver_picker` tool builds successfully and that `LINUX_SRC`
  points to a valid kernel tree.
* If compilation fails, verify that cross-compilation toolchains referenced by
  the `CROSS_COMPILE` environment variable are installed.
* Packaging errors usually indicate the build step did not produce the expected
  `target/release/driver_server` binary; rerun the build after fixing the
  underlying issue.

## Systemd integration

The build scripts can produce a systemd-based image. `scripts/build.sh` fetches and cross-builds systemd for arm and arm64, then installs it together with unit files from `files/systemd` into the root filesystem. The same process can be invoked with `make systemd-image`.

Unit files placed in `files/systemd` are copied to `/lib/systemd/system` at build time. `bash.service` is enabled by default. To enable or disable other services, create or remove the corresponding symlinks under `/etc/systemd/system/<target>.wants/` or run `systemctl enable`/`disable` after boot.

Systemd units interact with L4Re via capabilities exported in `files/cfg/bash.cfg`. Units that need a capability reference it through environment variables named `L4_CAP_<NAME>`. The file server demonstrates this pattern:

```
Environment="L4_CAP_GLOBAL_FS=global_fs" \
           "L4_CAP_LSB_ROOT=lsb_root" \
           "L4_CAP_VIRTIO_BLK=virtio_blk" \
           "L4_CAP_VIRTIO_BLK_IRQ=virtio_blk_irq" \
           "L4_CAP_IOMEM=iomem" \
           "L4_CAP_SCHED=scheduler"
```

These names correspond to capability handles defined in `files/cfg/bash.cfg`.

To extend the system, drop additional unit files into `files/systemd`, declare any required capability mappings in their `Environment` sections, and enable them via symlink or `systemctl enable`.

For debugging during boot, you can pass standard systemd options such as `systemd.log_level=debug` or `systemd.debug-shell` on the kernel command line (edit `files/cfg/bash.cfg` accordingly) and use the QEMU console launched by `scripts/runqemu.sh [IMAGE]` with tools like `journalctl` or `systemctl status`.
