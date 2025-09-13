This project re-introduces Rust for the L4Re microkernel.

Starting point was the work of the project [rustl4re](https://github.com/humenda/rustl4re).

## Building for ARM

Use `scripts/build_arm.sh` to build the project. By default, previous build
artifacts are removed before compilation. Passing `--no-clean` skips this
cleanup.

The script also accepts a `--test` flag which performs a brief QEMU boot using
the generated image `obj/l4/arm64/images/bootstrap_hello_arm_virt.elf`. The
script aborts if the QEMU run fails, providing a quick smoke test of the
build.
