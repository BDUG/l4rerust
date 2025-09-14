# Driver packaging workflow

The `tools/l4re-driver-wrap` helper bundles driver selection, build scaffolding
generation, compilation of the virtio-enabled server, and L4Re packaging into a
single command. It produces a package under `src/pkg/<driver>/` that can be
consumed by the L4Re build system.

## Basic usage

```
tools/l4re-driver-wrap --linux-src /path/to/linux
```

The script launches an interactive selector to choose a driver from the Linux
source tree. After extraction, the driver is wrapped and a package directory is
created.

## Using a configuration file

Re-running the workflow for a different driver can be automated via a simple
configuration file:

```
cat >driver.conf <<EOF
LINUX_SRC=/home/user/linux
DRIVER=e1000
EOF

tools/l4re-driver-wrap --config driver.conf
```

The `DRIVER` variable controls the package name. If omitted, the name from the
generated manifest is used.

## Troubleshooting

* Ensure the `driver_picker` tool builds successfully and that `LINUX_SRC`
  points to a valid kernel tree.
* If compilation fails, verify that cross-compilation toolchains referenced by
  the `CROSS_COMPILE` environment variable are installed.
* Packaging errors usually indicate the build step did not produce the expected
  `target/release/driver_server` binary; rerun the build after fixing the
  underlying issue.
