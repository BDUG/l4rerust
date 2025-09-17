# Systemd integration

The build scripts can produce a systemd-based image. `scripts/build.sh` fetches and cross-builds systemd for arm and arm64, then installs it together with unit files from `config/systemd` into the root filesystem. The same process can be invoked with `gmake systemd-image`.

Cross-compiling systemd requires Linux-targeted cross-compilers that provide
glibc libraries. Ensure `CROSS_COMPILE_ARM=arm-linux-gnueabihf-` and
`CROSS_COMPILE_ARM64=aarch64-linux-gnu-` are exported before launching the
build. The stripped-down `aarch64-elf-` toolchain is insufficient because it
omits `libcrypt` and other glibc libraries required by systemd.

Systemd also depends on libcap headers and `libcrypt` for each target
architecture. On Debian/Ubuntu hosts enable the `armhf` and `arm64`
architectures and install `libcap-dev:armhf`, `libcap-dev:arm64`,
`libxcrypt-dev:armhf`, and `libxcrypt-dev:arm64` (see the detailed commands in
[`docs/toolchains.md`](./toolchains.md)). The project Docker image will bundle
these packages once the container fix lands; manual installation is only needed
when building on your own host. If the systemd build fails due to missing
`libcrypt` libraries, install the packages and rerun
`scripts/build.sh --no-clean` to reuse the existing build directory.

Unit files placed in `config/systemd` are copied to `/lib/systemd/system` at build time. `bash.service` is enabled by default. To enable or disable other services, create or remove the corresponding symlinks under `/etc/systemd/system/<target>.wants/` or run `systemctl enable`/`disable` after boot.

Systemd units interact with L4Re via capabilities exported in `config/cfg/bash.cfg`. Units that need a capability reference it through environment variables named `L4_CAP_<NAME>`. The file server demonstrates this pattern:

```
Environment="L4_CAP_GLOBAL_FS=global_fs" \
           "L4_CAP_LSB_ROOT=lsb_root" \
           "L4_CAP_VIRTIO_BLK=virtio_blk" \
           "L4_CAP_VIRTIO_BLK_IRQ=virtio_blk_irq" \
           "L4_CAP_IOMEM=iomem" \
           "L4_CAP_SCHED=scheduler"
```

These names correspond to capability handles defined in `config/cfg/bash.cfg`.

To extend the system, drop additional unit files into `config/systemd`, declare any required capability mappings in their `Environment` sections, and enable them via symlink or `systemctl enable`.

For debugging during boot, you can pass standard systemd options such as `systemd.log_level=debug` or `systemd.debug-shell` on the kernel command line (edit `config/cfg/bash.cfg` accordingly) and use the QEMU console launched by `scripts/runqemu.sh [IMAGE]` with tools like `journalctl` or `systemctl status`.
