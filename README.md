# L4ReRust

L4ReRust brings the Rust programming language to the L4 Runtime Environment (L4Re) microkernel.

The project aims to let developers build system components in Rust with modern tooling while tracking the latest and greatest drivers from the Linux trunk.

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


## Build

After running `gmake setup` once to initialize the tree, invoking `gmake`
without arguments now builds the `systemd-image` target. This produces a
systemd-based boot image and serves as the primary build configuration. Other
gmake targets remain available—run them explicitly (for example,
`gmake bash-image` or `gmake examples`) when you need alternative outputs.

On a host with the necessary prerequisites installed, run:

**Linux:**
```bash
gmake
```


**Mac:**
```bash
CROSS_COMPILE=aarch64-linux-gnu- gmake
```

## Test 

After building, boot the image on your host with:

```bash
scripts/runqemu.sh        # launches bootstrap_hello_arm_virt.elf or the newest .elf image
```

If you need a fresh rebuild, rerun the script with `--clean` to remove previous
outputs before starting.

