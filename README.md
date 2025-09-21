# L4ReRust

L4ReRust brings Linux LSB and the Rust programming language to the L4 Runtime Environment (L4Re) microkernel.

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

## External Components and Overrides

The build script stages several external components, such as the OSv glibc
compatibility layer and supporting libraries, before generating images. Their
artifacts are written to `out/<component>/<arch>` by default, and each prefix
must contain `include`, `lib`, and `lib/pkgconfig` subdirectories so headers,
libraries, linker scripts, and pkg-config metadata are preserved.【F:scripts/lib/component_artifacts.sh†L12-L45】【F:pkg/glibc/Makefile†L1-L58】

Set `SYSTEMD_<COMPONENT>_PREFIX` to replace the staging directory for all
architectures, or `SYSTEMD_<COMPONENT>_PREFIX_<ARCH>` (`ARCH` is `ARM` or
`ARM64`) to override a specific architecture. For example, define
`SYSTEMD_GLIBC_PREFIX_ARM64=/path/to/glibc` to reuse a prebuilt glibc tree for
the 64-bit build without invoking the local builder.【F:scripts/lib/component_artifacts.sh†L19-L64】

