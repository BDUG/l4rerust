#!/usr/bin/env bash
set -euo pipefail

# Usage: build_arm.sh [--clean|--no-clean] [--test]
#   --clean     Remove previous build directories before building (default)
#   --no-clean  Skip removal of build directories
#   --test      Run a minimal QEMU boot test after building

clean=true
run_test=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      clean=true
      shift
      ;;
    --no-clean)
      clean=false
      shift
      ;;
    --test)
      run_test=true
      shift
      ;;
    *)
      echo "Usage: $0 [--clean|--no-clean] [--test]" >&2
      exit 1
      ;;
  esac
done

# Validate required tools
CROSS_COMPILE_ARM=${CROSS_COMPILE_ARM:-arm-linux-gnueabihf-}
CROSS_COMPILE_ARM64=${CROSS_COMPILE_ARM64:-aarch64-linux-gnu-}

required_tools=(
  git
  make
  "${CROSS_COMPILE_ARM}gcc"
  "${CROSS_COMPILE_ARM64}gcc"
)
for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool $tool not found" >&2
    exit 1
  fi
done

# Clone or update ham build tool
if [ ! -d ham ]; then
  git clone https://github.com/kernkonzept/ham.git
else
  (cd ham && git pull --ff-only)
fi
make -C ham

# Sync manifests using ham
(
  cd src &&
  ../ham/ham init -u https://github.com/kernkonzept/manifest.git &&
  ../ham/ham sync
)

# Start from a clean state
if [ "$clean" = true ]; then
  # Remove common build directories if they exist
  for dir in obj lib out; do
    if [ -d "$dir" ]; then
      rm -rf "$dir"
    fi
  done
fi

# Configure for ARM using setup script
export CROSS_COMPILE_ARM CROSS_COMPILE_ARM64
SETUP_CONFIG_ALL=1 ./setup config

# Build the tree including libc, Leo, and Rust crates
make

# Collect build artifacts
out_dir="out"
rm -rf "$out_dir"
mkdir -p "$out_dir"
find obj -type f \( -name '*.rlib' -o -name '*.elf' -o -name '*.img' -o -name '*.image' \) -exec cp {} "$out_dir" \;

echo "Artifacts placed in $out_dir"

if [ "$run_test" = true ]; then
  boot_img="obj/l4/arm64/images/bootstrap_hello_arm_virt.elf"
  if [ ! -f "$boot_img" ]; then
    echo "Boot image $boot_img not found" >&2
    exit 1
  fi
  if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
    echo "qemu-system-aarch64 not found" >&2
    exit 1
  fi
  echo "Running QEMU test..."
  if ! timeout 5s qemu-system-aarch64 -machine virt -cpu cortex-a57 -nographic -serial mon:stdio -kernel "$boot_img" >/dev/null; then
    echo "QEMU test run failed" >&2
    exit 1
  fi
fi
