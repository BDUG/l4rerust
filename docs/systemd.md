# Systemd integration

The build scripts can produce a systemd-based image. `scripts/build.sh` fetches and cross-builds systemd for arm and arm64, then installs it together with unit files from `config/systemd` into the root filesystem. The same process can be invoked with `gmake systemd-image`.

Cross-compiling systemd requires Linux-targeted cross-compilers that provide
glibc libraries. Ensure `CROSS_COMPILE_ARM=arm-linux-gnueabihf-` and
`CROSS_COMPILE_ARM64=aarch64-linux-gnu-` are exported before launching the
build. The stripped-down `aarch64-elf-` toolchain is insufficient because it
omits `libcrypt` and other glibc libraries required by systemd.

Systemd also depends on libcap headers and `libcrypt` for each target
architecture. By default `scripts/build.sh` downloads both libcap and
libxcrypt, cross-compiles them with the configured toolchains, and stages the
headers, libraries, and pkg-config files under `out/libcap/<arch>` and
`out/libcrypt/<arch>`. Meson picks up these self-contained artifacts when
 building systemd, so external `libxcrypt-dev` packages are no longer required
 in the cross sysroots. The systemd build also injects `out/libcap/<arch>/lib`
 (and `out/libcrypt/<arch>/lib`) into `LIBRARY_PATH`/`LD_LIBRARY_PATH` inside
 the build subshell before Meson/Ninja run, ensuring `${cross}gcc` searches the
 staged directories even when pkg-config resolves to bare `-lcap` or `-lcrypt`
 arguments. You may still install the distribution-provided packages if you
 prefer to rely on them, then rerun `scripts/build.sh --no-clean` to retry the
 systemd build without discarding prior work.

If you already maintain custom libcap or libxcrypt builds, set the
`SYSTEMD_LIBCAP_PREFIX` and/or `SYSTEMD_LIBCRYPT_PREFIX` environment variables
before invoking `scripts/build.sh`. Each variable should reference the root of
an installation that contains `include/`, `lib/`, and `lib/pkgconfig/`
subdirectories; the build script validates the layout and then skips the
download/compile logic. The overrides feed directly into Meson's pkg-config
search path, the temporary sysroot overlay, and the runtime staging step, so
the systemd build and resulting image rely exclusively on the caller-supplied
artifacts. When different directories are needed per architecture, use the
arch-specific forms (`SYSTEMD_LIBCAP_PREFIX_ARM`, `SYSTEMD_LIBCAP_PREFIX_ARM64`,
`SYSTEMD_LIBCRYPT_PREFIX_ARM`, and `SYSTEMD_LIBCRYPT_PREFIX_ARM64`) to supply
the appropriate paths. Leaving the environment variables unset restores the
original behavior that populates `out/libcap/<arch>` and `out/libcrypt/<arch>`
within the repository.

The generated systemd binary expects to resolve `libcap.so.2`, its
`libpsx.so` helper, and `libcrypt.so.1` at runtime. The packaging step copies
the shared objects from the configured libcap and libcrypt prefixes (falling
back to `out/libcap/arm64/lib` and `out/libcrypt/arm64/lib` when no overrides
are provided) into `/lib` within the root filesystem image and records matching
symlinks under `/usr/lib`. This ensures the dynamic loader can satisfy the
capability and crypt dependencies once the image boots. The
auxiliary utilities produced by libcap (`capsh`, `getcap`, `setcap`, etc.) are
not shipped by default, but you can copy them into the image manually if you
need them for debugging.

The libcap and libcrypt artifacts can also be published for other components
via the `pkg/libcap` and `pkg/libcrypt` packages. After `scripts/build.sh`
stages the headers, static/shared libraries, and pkg-config metadata under
`out/libcap/<arch>` and `out/libcrypt/<arch>`, run `gmake -C pkg/libcap install
L4ARCH=<arch> INSTDIR=<path>` and `gmake -C pkg/libcrypt install
L4ARCH=<arch> INSTDIR=<path>` to mirror the runtime layout under `$(INSTDIR)`.
This reproduces the SONAME symlinks created by `scripts/build.sh` so dependent
packages see the same directory structure they would at runtime.

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
