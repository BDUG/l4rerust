# Driver packaging workflow

The `tools/l4re-driver-wrap` helper bundles driver selection, build scaffolding
generation, compilation of the virtio-enabled server, and L4Re packaging into a
single command. It produces a package under `pkg/<driver>/` that can be
consumed by the L4Re build system.

## Basic usage

```
tools/l4re-driver-wrap --linux-src /path/to/linux
```

When invoked from an interactive terminal with the external
[`dialog`](https://invisible-island.net/dialog/dialog.html) utility available,
the wrapper launches `tools/driver_picker_menu.sh`. The helper gathers the
catalog via `driver_picker --list`, presents a menu to select a subsystem and a
driver, and finally runs the extraction pipeline with
`driver_picker --driver <symbol> --subsystem <name>`. The resulting output still
mirrors the traditional format:

```
Workspace: /tmp/l4re-driver.XXXXXX
Manifest written to /tmp/l4re-driver.XXXXXX/driver.yaml
```

If `dialog` is missing or the session is non-interactive the workflow falls back
to the original `cargo run -p driver_picker` prompts.

To preview the available drivers without extracting anything, run:

```
cargo run -p driver_picker -- --linux-src /path/to/linux --list --format json
```

The picker can also operate non-interactively when both the subsystem and
driver are known ahead of time:

```
cargo run -p driver_picker -- \
  --linux-src /path/to/linux \
  --subsystem net \
  --driver E1000
```

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

* Ensure the `tools/driver_picker` tool builds successfully and that `LINUX_SRC`
  points to a valid kernel tree. Installing `dialog` enables the menu-based
  picker used by `tools/l4re-driver-wrap` and `tools/driver_picker_menu.sh`.
* If compilation fails, verify that cross-compilation toolchains referenced by
  the `CROSS_COMPILE` environment variable are installed.
* Packaging errors usually indicate the build step did not produce the expected
  `target/release/driver_server` binary; rerun the build after fixing the
  underlying issue.
