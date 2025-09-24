# L4ReRust

L4ReRust brings Linux LSB and the Rust programming language to the L4 Runtime Environment (L4Re) microkernel.

## Host prerequisites

Install the following tools before invoking `scripts/build.sh`:

- A Rust toolchain that provides both `cargo` and `rustc` (for example, via [`rustup`](https://rustup.rs/)).

The sections below describe additional tooling required by specific parts of the build.

## Installing tool 'ham'

The build scripts rely on the [`ham`](https://github.com/kernkonzept/ham)
tool to synchronize L4Re manifests. The executable must reside at
`ham/ham` relative to the repository root.

Clone and build `ham` from source:

```bash
git clone https://github.com/kernkonzept/ham.git ham
(cd ham && gmake)
```

Ensure the binary is executable and available on your `PATH` if you wish to
invoke it globally.

```bash
export PATH=$PWD/ham/:$PATH
```

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

Pass `--clean` (or select “Clean out directory before build” in the interactive
menu) to remove previous build directories.
existing directories for incremental builds; `--no-clean` enforces this reuse in
automation. Build artifacts are placed under `out/`.

The interactive `dialog` menu also lets you review and edit the cross-compiler
prefixes before building. Leave a field blank to fall back to the detected
defaults or mirror the ARM64 prefix into the general `CROSS_COMPILE` setting.

## Documentation

- [Integrating musl libc with L4Re](docs/musl_integration_whitepaper.md)
  explains how the musl runtime is built, packaged, and made available to the
  L4Re kernel and Rust toolchain.

