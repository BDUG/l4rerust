#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"

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


detect_cross_compilers
validate_tools

run_with_timeout() {
  local duration="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${duration}s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${duration}s" "$@"
  else
    python3 - "$duration" "$@" <<'PYTHON'
import subprocess, sys
timeout=int(sys.argv[1]); cmd=sys.argv[2:]
proc=subprocess.Popen(cmd)
try:
    proc.wait(timeout)
    sys.exit(proc.returncode)
except subprocess.TimeoutExpired:
    proc.kill()
    sys.exit(124)
PYTHON
  fi
}

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

# Build systemd for ARM and ARM64
build_systemd() {
  local arch="$1" cross="$2" cpu="$3"
  local out_dir="obj/systemd/$arch"
  if [ -f "$out_dir/systemd" ]; then
    echo "systemd for $arch already built, skipping"
    return
  fi
  mkdir -p "$out_dir"
  (
    cd "$systemd_src_dir"
    builddir="build-$arch"
    rm -rf "$builddir"
    cat > cross.txt <<EOF
[binaries]
c = '${cross}gcc'
ar = '${cross}ar'
strip = '${cross}strip'

[host_machine]
system = 'linux'
cpu_family = '$cpu'
cpu = '$cpu'
endian = 'little'
EOF
    meson setup "$builddir" --cross-file cross.txt --prefix=/usr
    ninja -C "$builddir" systemd || ninja -C "$builddir"
    DESTDIR="$repo_root/$out_dir/root" meson install -C "$builddir"
    cp "$repo_root/$out_dir/root/lib/systemd/systemd" "$repo_root/$out_dir/"
  )
}

# Build OpenSSH for ARM and ARM64
build_openssh() {
  local arch="$1" cross="$2" host="$3"
  local out_dir="obj/openssh/$arch"
  if [ -f "$out_dir/sshd" ]; then
    echo "openssh for $arch already built, skipping"
    return
  fi
  mkdir -p "$out_dir"
  (
    cd "$openssh_src_dir"
    make distclean >/dev/null 2>&1 || true
    CC="${cross}gcc" AR="${cross}ar" RANLIB="${cross}ranlib" LDFLAGS=-static \
      ./configure --host="$host" --with-privsep-path=/var/empty --disable-strip
    make clean
    CC="${cross}gcc" AR="${cross}ar" RANLIB="${cross}ranlib" LDFLAGS=-static \
      make sshd
    cp sshd "$repo_root/$out_dir/"
  )
}

need_systemd=false
for arch in arm arm64; do
  if [ ! -f "obj/systemd/$arch/systemd" ]; then
    need_systemd=true
    break
  fi
done

if [ "$need_systemd" = true ]; then
  SYSTEMD_VERSION=255.4
  SYSTEMD_URL="https://github.com/systemd/systemd-stable/archive/refs/tags/v${SYSTEMD_VERSION}.tar.gz"
  systemd_src_dir=$(mktemp -d src/systemd-XXXXXX)
  curl -L "$SYSTEMD_URL" | tar -xz -C "$systemd_src_dir" --strip-components=1
  build_systemd arm "$CROSS_COMPILE_ARM" arm
  build_systemd arm64 "$CROSS_COMPILE_ARM64" aarch64
  rm -rf "$systemd_src_dir"
else
  echo "systemd for arm and arm64 already built, skipping"
fi

# Build OpenSSH for ARM and ARM64
need_openssh=false
for arch in arm arm64; do
  if [ ! -f "obj/openssh/$arch/sshd" ]; then
    need_openssh=true
    break
  fi
done

if [ "$need_openssh" = true ]; then
  OPENSSH_VERSION=9.6p1
  OPENSSH_URL="https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz"
  openssh_src_dir=$(mktemp -d src/openssh-XXXXXX)
  curl -L "$OPENSSH_URL" | tar -xz -C "$openssh_src_dir" --strip-components=1
  build_openssh arm "$CROSS_COMPILE_ARM" arm-linux-gnueabihf
  build_openssh arm64 "$CROSS_COMPILE_ARM64" aarch64-linux-gnu
  rm -rf "$openssh_src_dir"
else
  echo "openssh for arm and arm64 already built, skipping"
fi

# Link the OpenSSH server binary into the package directory so the
# L4Re build system can pick it up when creating images.
mkdir -p src/pkg/openssh
for arch in arm arm64; do
  if [ -f "obj/openssh/$arch/sshd" ]; then
    ln -sf ../../obj/openssh/$arch/sshd src/pkg/openssh/sshd
  fi
done

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

# Set up SSH configuration and host keys
mkdir -p files/lsb_root/etc/ssh
debugfs -w -R "mkdir /etc/ssh" "$lsb_img" >/dev/null
chmod 0644 files/lsb_root/etc/ssh/sshd_config
hostkey_tmp=$(mktemp)
ssh-keygen -t rsa -N '' -f "$hostkey_tmp" >/dev/null
cp "$hostkey_tmp" files/lsb_root/etc/ssh/ssh_host_rsa_key
cp "$hostkey_tmp.pub" files/lsb_root/etc/ssh/ssh_host_rsa_key.pub
chmod 600 files/lsb_root/etc/ssh/ssh_host_rsa_key files/lsb_root/etc/ssh/ssh_host_rsa_key.pub
debugfs -w -R "write files/lsb_root/etc/ssh/sshd_config /etc/ssh/sshd_config" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0644 /etc/ssh/sshd_config" "$lsb_img" >/dev/null
debugfs -w -R "write $hostkey_tmp /etc/ssh/ssh_host_rsa_key" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0600 /etc/ssh/ssh_host_rsa_key" "$lsb_img" >/dev/null
debugfs -w -R "write $hostkey_tmp.pub /etc/ssh/ssh_host_rsa_key.pub" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0600 /etc/ssh/ssh_host_rsa_key.pub" "$lsb_img" >/dev/null
rm "$hostkey_tmp" "$hostkey_tmp.pub"

# Install systemd into the root filesystem image and staging area
sys_root="obj/systemd/arm64/root"
if [ -d "$sys_root" ]; then
  mkdir -p files/lsb_root/usr/lib/systemd
  mkdir -p files/lsb_root/lib/systemd
  if [ -d "$sys_root/usr/lib/systemd" ]; then
    cp -r "$sys_root/usr/lib/systemd/"* files/lsb_root/usr/lib/systemd/ 2>/dev/null || true
  fi
  if [ -f "$sys_root/lib/systemd/systemd" ]; then
    cp "$sys_root/lib/systemd/systemd" files/lsb_root/lib/systemd/systemd
    cp "$sys_root/lib/systemd/systemd" files/lsb_root/usr/lib/systemd/systemd
    debugfs -w -R "mkdir /lib/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "mkdir /usr/lib/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "write $sys_root/lib/systemd/systemd /lib/systemd/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "chmod 0755 /lib/systemd/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "write $sys_root/lib/systemd/systemd /usr/lib/systemd/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "chmod 0755 /usr/lib/systemd/systemd" "$lsb_img" >/dev/null
    if [ -d "$sys_root/usr/lib/systemd" ]; then
      find "$sys_root/usr/lib/systemd" -type d | while read -r d; do
        rel="${d#$sys_root}"
        debugfs -w -R "mkdir $rel" "$lsb_img" >/dev/null || true
      done
      find "$sys_root/usr/lib/systemd" -type f | while read -r f; do
        rel="${f#$sys_root}"
        debugfs -w -R "write $f $rel" "$lsb_img" >/dev/null
        debugfs -w -R "chmod 0644 $rel" "$lsb_img" >/dev/null
      done
    fi
  fi
fi

# Install systemd unit files into the image
units_dir="files/systemd"
if [ -d "$units_dir" ]; then
  mkdir -p files/lsb_root/lib/systemd/system
  debugfs -w -R "mkdir /lib/systemd/system" "$lsb_img" >/dev/null || true
  for unit in "$units_dir"/*.service; do
    [ -f "$unit" ] || continue
    base="$(basename "$unit")"
    cp "$unit" files/lsb_root/lib/systemd/system/
    debugfs -w -R "write $unit /lib/systemd/system/$base" "$lsb_img" >/dev/null
    debugfs -w -R "chmod 0644 /lib/systemd/system/$base" "$lsb_img" >/dev/null
  done
fi

# Enable services
enable_service() {
  local name="$1"
  local unit="files/systemd/${name}.service"
  if [ -f "$unit" ]; then
    mkdir -p files/lsb_root/etc/systemd/system/multi-user.target.wants
    ln -sf ../../../../lib/systemd/system/${name}.service \
      files/lsb_root/etc/systemd/system/multi-user.target.wants/${name}.service
    debugfs -w -R "mkdir /etc/systemd" "$lsb_img" >/dev/null || true
    debugfs -w -R "mkdir /etc/systemd/system" "$lsb_img" >/dev/null || true
    debugfs -w -R "mkdir /etc/systemd/system/multi-user.target.wants" "$lsb_img" >/dev/null || true
    debugfs -w -R "symlink /lib/systemd/system/${name}.service /etc/systemd/system/multi-user.target.wants/${name}.service" "$lsb_img" >/dev/null
  fi
}

enable_service bash
enable_service sshd

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
  if ! run_with_timeout 5 qemu-system-aarch64 -machine virt -cpu cortex-a57 -nographic -serial mon:stdio -kernel "$boot_img" >/dev/null; then
    echo "QEMU test run failed" >&2
    exit 1
  fi
fi
