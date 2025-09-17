# Toolchains

## Cross-compilation toolchains

Both the `setup` script and `scripts/build.sh` look for compiler prefixes via
the `CROSS_COMPILE_ARM` and `CROSS_COMPILE_ARM64` environment variables.
System components that rely on glibc, such as systemd, must be built with
Linux-targeted toolchains that provide those libraries. Use the
`arm-linux-gnueabihf-` and `aarch64-linux-gnu-` prefixes when setting up these
cross-compilers. If they are not already available, they can be installed via
your distribution, Homebrew, or built with
[crosstool-ng](https://crosstool-ng.github.io/).

### Installing compilers on Debian/Ubuntu

1. Update the package index:

   ```bash
   sudo apt update
   ```

2. Install the cross-compilers:

   ```bash
   sudo apt install g++-arm-linux-gnueabihf g++-aarch64-linux-gnu
   ```

3. Verify the installation:

   ```bash
   arm-linux-gnueabihf-g++ --version
   aarch64-linux-gnu-g++ --version
   ```

4. Install target headers and libraries that are not built in-tree:

   ```bash
   sudo dpkg --add-architecture armhf
   sudo dpkg --add-architecture arm64
   sudo apt update
   sudo apt install libxcrypt-dev:armhf libxcrypt-dev:arm64
   ```

   `scripts/build.sh` downloads and stages libcap locally, so only the
   `libxcrypt-dev` packages are required to provide `libcrypt` within each
   cross sysroot. The matching `libxcrypt-dev` packages provide `libcrypt`
   within the cross sysroots. Without them the systemd build fails while
   linking. After installing the missing packages re-run
   `scripts/build.sh --no-clean` to retry without discarding prior work.

After installing a toolchain, add its `bin` directory to your `PATH` and set
the expected prefixes:

```bash
export PATH=/path/to/toolchain/bin:$PATH
export CROSS_COMPILE_ARM=arm-linux-gnueabihf-
export CROSS_COMPILE_ARM64=aarch64-linux-gnu-
```

Verify each compiler is on your `PATH` before invoking `scripts/build.sh` or
`setup`.

When these variables are unset, the scripts attempt to choose sensible
defaults based on `uname`. Override any non-Linux prefix (such as
`aarch64-elf-`) with `aarch64-linux-gnu-` before building systemd or any other
component that links against glibc-provided libraries.

The build scripts rely on GNU utilities such as `timeout`, `stat`, and
`truncate`. Ensure GNU versions of these tools are available in your `PATH`;
on macOS they are installed by the `coreutils` package with a `g` prefix. The
build scripts automatically expose these tools under their expected names.

### Troubleshooting

- `Required tool arm-linux-gnueabihf-g++ not found` indicates the ARM compiler
  is missing or not on your `PATH`. Install `g++-arm-linux-gnueabihf` and
  ensure `CROSS_COMPILE_ARM=arm-linux-gnueabihf-` is exported.

## macOS (Apple Silicon)

On Apple Silicon hosts, Homebrew provides the required build tools and cross
compilers:

```bash
brew install qemu e2fsprogs coreutils meson ninja pkg-config
brew install arm-linux-gnueabihf-g++ aarch64-linux-gnu-g++
```

The build scripts automatically run `brew --prefix` for `arm-linux-gnueabihf-g++`,
`aarch64-linux-gnu-g++`, and `e2fsprogs` and prepend their `bin` directories to
`PATH`. Define the compiler prefixes expected by the build scripts:

```bash
export CROSS_COMPILE_ARM=arm-linux-gnueabihf-
export CROSS_COMPILE_ARM64=aarch64-linux-gnu-
```

macOS does not ship GNU `timeout` or several other utilities required by the
build. The `coreutils` formula installs them with a `g` prefix (e.g.,
`gtimeout`). The build scripts automatically create aliases so these tools are
available as `timeout`, `stat`, and `truncate`.

With the environment set up, a smoke test of the build can be run with:

```bash
CROSS_COMPILE_ARM=arm-linux-gnueabihf- \
CROSS_COMPILE_ARM64=aarch64-linux-gnu- \
scripts/build.sh --test
```

Some tools, such as `mke2fs` from `e2fsprogs`, live outside Homebrew's default
`bin` prefix, but the build scripts add these directories automatically.

