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
  curl
  "${CROSS_COMPILE_ARM}gcc"
  "${CROSS_COMPILE_ARM64}gcc"
  mke2fs
  debugfs
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

# Build the Rust libc crate so other crates can link against it
(
  cd src/l4rust
  cargo build -p l4re-libc --release
)
# Ensure Rust crates pick up the freshly built static libc
export LIBRARY_PATH="$(pwd)/src/l4rust/target/release:${LIBRARY_PATH:-}"

# Build a statically linked Bash for ARM and ARM64
build_bash() {
  local arch="$1" cross="$2" host="$3"
  local out_dir="obj/bash/$arch"
  if [ -f "$out_dir/bash" ]; then
    echo "bash for $arch already built, skipping"
    return
  fi
  mkdir -p "$out_dir"
  (
    cd "$bash_src_dir"
    make distclean >/dev/null 2>&1 || true
    CC="${cross}gcc" AR="${cross}ar" RANLIB="${cross}ranlib" \
      ./configure --host="$host" --without-bash-malloc
    make clean
    CC="${cross}gcc" AR="${cross}ar" RANLIB="${cross}ranlib" \
      make STATIC_LDFLAGS=-static
    cp bash "$repo_root/$out_dir/"
  )
}
repo_root=$(pwd)

need_bash=false
for arch in arm arm64; do
  if [ ! -f "obj/bash/$arch/bash" ]; then
    need_bash=true
    break
  fi
done

if [ "$need_bash" = true ]; then
  BASH_VERSION=5.2.21
  BASH_URL="https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  bash_src_dir=$(mktemp -d src/bash-XXXXXX)
  curl -L "$BASH_URL" | tar -xz -C "$bash_src_dir" --strip-components=1
  build_bash arm "$CROSS_COMPILE_ARM" arm-linux-gnueabihf
  build_bash arm64 "$CROSS_COMPILE_ARM64" aarch64-linux-gnu
  rm -rf "$bash_src_dir"
else
  echo "bash for arm and arm64 already built, skipping"
fi

# Build the tree including libc, Leo, and Rust crates
make

# Create a minimal LSB root filesystem image
lsb_img="files/lsb_root/lsb_root.img"
rm -f "$lsb_img"
mkdir -p "$(dirname "$lsb_img")"
dd if=/dev/zero of="$lsb_img" bs=1M count=8
mke2fs -F "$lsb_img" >/dev/null
for d in /bin /etc /usr /usr/bin; do
  debugfs -w -R "mkdir $d" "$lsb_img" >/dev/null
done
tmpfile=$(mktemp)
cat <<'EOF' > "$tmpfile"
DISTRIB_ID=L4Re
DISTRIB_RELEASE=1.0
DISTRIB_DESCRIPTION="L4Re root image"
EOF
debugfs -w -R "write $tmpfile /etc/lsb-release" "$lsb_img" >/dev/null
rm "$tmpfile"
debugfs -w -R "write obj/bash/arm64/bash /bin/sh" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0755 /bin/sh" "$lsb_img" >/dev/null
debugfs -w -R "write obj/bash/arm64/bash /bin/bash" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0755 /bin/bash" "$lsb_img" >/dev/null

# Collect build artifacts
out_dir="out"
rm -rf "$out_dir"
mkdir -p "$out_dir"
find obj -type f \( -name '*.rlib' -o -name '*.elf' -o -name '*.img' -o -name '*.image' \) -exec cp {} "$out_dir" \;
cp "$lsb_img" "$out_dir/"

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
