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

## Bootable L4Re image with systemd and Bash

To produce a bootable image that launches systemd (as `/sbin/init`) and starts
the bundled Bash shell service, run the standard build and then load the image
into QEMU:

```bash
scripts/setup.sh --non-interactive   # fetch and configure the L4Re tree
scripts/build.sh --no-clean          # build L4Re, systemd, Bash, and stage the image
scripts/runqemu.sh                   # boot the freshest image under QEMU
```

Boot artifacts are staged under `distribution/images/`. The
`lsb_root.img` root filesystem image contains the packaged Bash shell and
systemd (installed as `/sbin/init`), while the
`bootstrap_bash_arm_virt.uimage` boot image loads that filesystem together with
the required L4Re components to start the file server, network server, and an
interactive Bash console.

