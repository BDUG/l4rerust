# Systemd integration

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
