#!/usr/bin/env bash
set -euo pipefail

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
rm -rf obj

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
