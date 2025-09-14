# Toolchains

## Cross-compilation toolchains

Both the `setup` script and `scripts/build.sh` look for compiler prefixes
via the `CROSS_COMPILE_ARM` and `CROSS_COMPILE_ARM64` environment variables.
Typical prefixes for Linux-targeted toolchains are `arm-linux-gnueabihf-` and
`aarch64-linux-gnu-`, while macOS now uses the `aarch64-elf-` prefix by default.
If these cross-compilers are not already available, they can be installed via
your distribution, Homebrew, or built with
[crosstool-ng](https://crosstool-ng.github.io/).

If `setup` or `scripts/build.sh` report a failure such as
`Required tool aarch64-elf-gcc not found`, an AArch64 cross compiler is
missing. Install one with your package manager, e.g.
`brew install aarch64-elf-gcc` or, on Linux hosts, `sudo apt install
gcc-aarch64-linux-gnu`, and export the appropriate prefix (`CROSS_COMPILE_ARM64=aarch64-elf-`
or `aarch64-linux-gnu-`).

After installing a toolchain, add its `bin` directory to your `PATH` and set
the expected prefixes:

```bash
export PATH=/path/to/toolchain/bin:$PATH
export CROSS_COMPILE_ARM=arm-linux-gnueabihf-
export CROSS_COMPILE_ARM64=aarch64-elf-
```

Verify the compiler is on your `PATH` (e.g., `aarch64-elf-gcc --version`)
before invoking `scripts/build.sh` or `setup`.

When these variables are unset, the scripts attempt to choose sensible
defaults based on `uname`.

The build scripts rely on several GNU utilities such as `timeout`, `stat`, and
`truncate`. Ensure GNU versions of these tools are available in your `PATH`;
on macOS they are installed by the `coreutils` package with a `g` prefix.

## macOS (Apple Silicon)

On Apple Silicon hosts, Homebrew provides the required build tools and cross
compilers:

```bash
brew install qemu e2fsprogs coreutils meson ninja pkg-config
brew install arm-linux-gnueabihf-gcc aarch64-elf-gcc
```

Ensure the Homebrew prefixes are in your `PATH` and define the compiler
prefixes expected by the build scripts:

```bash
export PATH="$(brew --prefix e2fsprogs)/bin:$(brew --prefix arm-linux-gnueabihf-gcc)/bin:$(brew --prefix aarch64-elf-gcc)/bin:$PATH"
export CROSS_COMPILE_ARM=arm-linux-gnueabihf-
export CROSS_COMPILE_ARM64=aarch64-elf-
```

macOS does not ship GNU `timeout` or several other GNU utilities required by
the build. The `coreutils` formula installs them with a `g` prefix (e.g.,
`gtimeout`). Either invoke these `g`-prefixed tools directly or alias them to
the expected names:

```bash
alias timeout=gtimeout
```

With the environment set up, a smoke test of the build can be run with:

```bash
CROSS_COMPILE_ARM=arm-linux-gnueabihf- \
CROSS_COMPILE_ARM64=aarch64-elf- \
scripts/build.sh --test
```

Some tools, such as `mke2fs` from `e2fsprogs`, live outside Homebrew's default
`bin` prefix; the `PATH` example above includes these locations.

