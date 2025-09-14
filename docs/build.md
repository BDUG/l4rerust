# Build

## Containerized build

If cross-compilers or required GNU utilities are not available on the host,
the project can be built inside a Docker container. Ensure
[Docker](https://www.docker.com/) is installed and run:

```bash
scripts/docker_build.sh --test
```

The script builds the image if needed and invokes `scripts/build.sh` inside the
container. The `--test` flag performs a brief QEMU boot to verify the build.
All toolchains and GNU utilities are provided by the container, so nothing
else needs to be installed on the host.

## Building for ARM

Use `scripts/build.sh` to build the project. By default, previous build
artifacts are removed before compilation. Passing `--no-clean` skips this
cleanup.

The script also accepts a `--test` flag which performs a brief QEMU boot using
the generated image `obj/l4/arm64/images/bootstrap_hello_arm_virt.elf`. The
script aborts if the QEMU run fails, providing a quick smoke test of the
build.

Built components and images are collected under the `out/` directory.

The build process first compiles the `l4re-libc` crate to provide a static
libc for the Rust components. The resulting library is made available through
the `LIBRARY_PATH` environment variable so that subsequent Rust crates link
against it automatically.

To rebuild manually outside of the script:

```
cd src/l4rust
cargo build -p l4re-libc --release
export LIBRARY_PATH=$(pwd)/target/release:${LIBRARY_PATH}
cd -
make
```

Ensuring `LIBRARY_PATH` is set correctly allows the Rust crates to link against
the freshly built static libc.

