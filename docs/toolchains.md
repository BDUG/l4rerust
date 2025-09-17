# Toolchains

## Cross-compilation toolchains

Both the `setup` script and `scripts/build.sh` look for compiler prefixes via
the `CROSS_COMPILE_ARM` and `CROSS_COMPILE_ARM64` environment variables.
Typical prefixes for Linux-targeted toolchains are `arm-linux-gnueabihf-` and
`aarch64-linux-gnu-`, while macOS now uses the `aarch64-elf-` prefix by
default. If these cross-compilers are not already available, they can be
installed via your distribution, Homebrew, or built with
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

4. Install target headers required for cross-building systemd:

   ```bash
   sudo dpkg --add-architecture armhf
   sudo dpkg --add-architecture arm64
   sudo apt update
   sudo apt install libcap-dev:armhf libcap-dev:arm64
   ```

   The systemd build expects libcap headers for each target architecture. The
   provided Docker image will include these packages once the container fix
   lands; manual installation is only necessary when building directly on your
   host machine.

After installing a toolchain, add its `bin` directory to your `PATH` and set
the expected prefixes:

```bash
export PATH=/path/to/toolchain/bin:$PATH
export CROSS_COMPILE_ARM=arm-linux-gnueabihf-
export CROSS_COMPILE_ARM64=aarch64-elf-
```

Verify each compiler is on your `PATH` before invoking `scripts/build.sh` or
`setup`.

When these variables are unset, the scripts attempt to choose sensible
defaults based on `uname`; `CROSS_COMPILE_ARM64` falls back to the
`aarch64-elf-` prefix.

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
brew install arm-linux-gnueabihf-g++ aarch64-elf-g++
```

The build scripts automatically run `brew --prefix` for `arm-linux-gnueabihf-g++`,
`aarch64-elf-g++`, and `e2fsprogs` and prepend their `bin` directories to
`PATH`. Define the compiler prefixes expected by the build scripts:

```bash
export CROSS_COMPILE_ARM=arm-linux-gnueabihf-
# CROSS_COMPILE_ARM64 defaults to aarch64-elf-
```

macOS does not ship GNU `timeout` or several other utilities required by the
build. The `coreutils` formula installs them with a `g` prefix (e.g.,
`gtimeout`). The build scripts automatically create aliases so these tools are
available as `timeout`, `stat`, and `truncate`.

With the environment set up, a smoke test of the build can be run with:

```bash
CROSS_COMPILE_ARM=arm-linux-gnueabihf- \
scripts/build.sh --test  # CROSS_COMPILE_ARM64 defaults to aarch64-elf-
```

Some tools, such as `mke2fs` from `e2fsprogs`, live outside Homebrew's default
`bin` prefix, but the build scripts add these directories automatically.

