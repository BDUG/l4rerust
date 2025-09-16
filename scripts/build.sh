#!/usr/bin/env bash
set -euo pipefail

echo "Entering build container"
trap 'echo "Leaving build container"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"
cd "$REPO_ROOT"

# Usage: build.sh [--clean|--no-clean]
#   --clean     Remove previous build directories before building (default)
#   --no-clean  Skip removal of build directories
clean=true
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
    *)
      echo "Usage: $0 [--clean|--no-clean]" >&2
      exit 1
      ;;
  esac
done

# Set up the L4Re environment (l4re-core and ham)
"$SCRIPT_DIR/setup_l4re_env.sh"
HAM_BIN="$(resolve_path "$SCRIPT_DIR/../ham/ham")"

# Use ham to keep the manifest consistent with the latest l4re-core
(
  cd "$REPO_ROOT/src" &&
  "$HAM_BIN" init -u https://github.com/kernkonzept/manifest.git &&
  "$HAM_BIN" sync l4re-core
)

detect_cross_compilers
validate_tools

ARTIFACTS_DIR="out"

# Start from a clean state if requested
if [ "$clean" = true ]; then
  "$SCRIPT_DIR/setup.sh" clean
fi

mkdir -p "$ARTIFACTS_DIR"

# Configure for ARM using setup script
export CROSS_COMPILE_ARM CROSS_COMPILE_ARM64
# Run the setup tool. If a pre-generated configuration is available, reuse it
# to avoid the interactive `config` step.
if [ -f /workspace/.config ]; then
  echo "Using configuration from /workspace/.config"
  mkdir -p obj
  cp /workspace/.config obj/.config
elif [ -f "$SCRIPT_DIR/l4re.config" ]; then
  echo "Using configuration from scripts/l4re.config"
  mkdir -p obj
  cp "$SCRIPT_DIR/l4re.config" obj/.config
else
  "$SCRIPT_DIR/setup.sh" config
fi
"$SCRIPT_DIR/setup.sh" --non-interactive

# Build the Rust libc crate so other crates can link against it
cargo build -p l4re-libc --release
# Ensure Rust crates pick up the freshly built static libc
export LIBRARY_PATH="$(pwd)/target/release:${LIBRARY_PATH:-}"

# Build a statically linked Bash for ARM and ARM64
build_bash() {
  local arch="$1" cross="$2"
  local triple="$(${cross}g++ -dumpmachine)"
  if [[ "$triple" != *-linux-* && "$triple" != *-elf* ]]; then
    echo "${cross}g++ targets '$triple', which is neither a Linux nor ELF target" >&2
    exit 1
  fi
  local host="$triple"
  local cpu="${triple%%-*}"
  local out_dir="$ARTIFACTS_DIR/bash/$arch"
  if [ -f "$out_dir/bash" ]; then
    echo "bash for $arch already built, skipping"
    return
  fi
  mkdir -p "$out_dir"
  (
    cd "$bash_src_dir"
    gmake distclean >/dev/null 2>&1 || true
    CC="${cross}g++" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" \
      ./configure --host="$host" --without-bash-malloc
    gmake clean
    CC="${cross}g++" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" \
      gmake STATIC_LDFLAGS=-static
    cp bash "$REPO_ROOT/$out_dir/"
  )
}

need_bash=false
for arch in arm arm64; do
  if [ ! -f "$ARTIFACTS_DIR/bash/$arch/bash" ]; then
    need_bash=true
    break
  fi
done

if [ "$need_bash" = true ]; then
  BASH_VERSION=5.2.21
  BASH_URL="https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz"
  bash_src_dir=$(mktemp -d src/bash-XXXXXX)
  curl -L "$BASH_URL" | tar -xz -C "$bash_src_dir" --strip-components=1
  build_bash arm "$CROSS_COMPILE_ARM"
  build_bash arm64 "$CROSS_COMPILE_ARM64"
  rm -rf "$bash_src_dir"
else
  echo "bash for arm and arm64 already built, skipping"
fi

# Build systemd for ARM and ARM64
build_systemd() {
  local arch="$1" cross="$2"
  local triple="$(${cross}g++ -dumpmachine)"
  if [[ "$triple" != *-linux-* && "$triple" != *-elf* ]]; then
    echo "${cross}g++ targets '$triple', which is neither a Linux nor ELF target" >&2
    exit 1
  fi
  local host="$triple"
  local cpu="${triple%%-*}"
  local out_dir="$ARTIFACTS_DIR/systemd/$arch"
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
c = '${cross}g++'
ar = '${cross}ar'
strip = '${cross}strip'

[host_machine]
system = 'linux'
cpu_family = '${cpu}'
cpu = '${cpu}'
endian = 'little'
EOF
    meson setup "$builddir" --cross-file cross.txt --prefix=/usr
    ninja -C "$builddir" systemd || ninja -C "$builddir"
    DESTDIR="$REPO_ROOT/$out_dir/root" meson install -C "$builddir"
    cp "$REPO_ROOT/$out_dir/root/lib/systemd/systemd" "$REPO_ROOT/$out_dir/"
  )
}

# Build OpenSSH for ARM and ARM64
build_openssh() {
  local arch="$1" cross="$2"
  local triple="$(${cross}g++ -dumpmachine)"
  if [[ "$triple" != *-linux-* && "$triple" != *-elf* ]]; then
    echo "${cross}g++ targets '$triple', which is neither a Linux nor ELF target" >&2
    exit 1
  fi
  local host="$triple"
  local out_dir="$ARTIFACTS_DIR/openssh/$arch"
  if [ -f "$out_dir/sshd" ]; then
    echo "openssh for $arch already built, skipping"
    return
  fi
  mkdir -p "$out_dir"
  (
    cd "$openssh_src_dir"
    gmake distclean >/dev/null 2>&1 || true
    CC="${cross}g++" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" LDFLAGS=-static \
      ./configure --host="$host" --with-privsep-path=/var/empty --disable-strip
    gmake clean
    CC="${cross}g++" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" LDFLAGS=-static \
      gmake sshd
    cp sshd "$REPO_ROOT/$out_dir/"
  )
}

need_systemd=false
for arch in arm arm64; do
  if [ ! -f "$ARTIFACTS_DIR/systemd/$arch/systemd" ]; then
    need_systemd=true
    break
  fi
done

if [ "$need_systemd" = true ]; then
  SYSTEMD_VERSION=255.4
  SYSTEMD_URL="https://github.com/systemd/systemd-stable/archive/refs/tags/v${SYSTEMD_VERSION}.tar.gz"
  systemd_src_dir=$(mktemp -d src/systemd-XXXXXX)
  curl -L "$SYSTEMD_URL" | tar -xz -C "$systemd_src_dir" --strip-components=1
  build_systemd arm "$CROSS_COMPILE_ARM"
  build_systemd arm64 "$CROSS_COMPILE_ARM64"
  rm -rf "$systemd_src_dir"
else
  echo "systemd for arm and arm64 already built, skipping"
fi

# Build OpenSSH for ARM and ARM64
need_openssh=false
for arch in arm arm64; do
  if [ ! -f "$ARTIFACTS_DIR/openssh/$arch/sshd" ]; then
    need_openssh=true
    break
  fi
done

if [ "$need_openssh" = true ]; then
  OPENSSH_VERSION=9.6p1
  OPENSSH_URL="https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz"
  openssh_src_dir=$(mktemp -d src/openssh-XXXXXX)
  curl -L "$OPENSSH_URL" | tar -xz -C "$openssh_src_dir" --strip-components=1
  build_openssh arm "$CROSS_COMPILE_ARM"
  build_openssh arm64 "$CROSS_COMPILE_ARM64"
  rm -rf "$openssh_src_dir"
else
  echo "openssh for arm and arm64 already built, skipping"
fi

# Link the OpenSSH server binary into the package directory so the
# L4Re build system can pick it up when creating images.
mkdir -p pkg/openssh
for arch in arm arm64; do
  if [ -f "$ARTIFACTS_DIR/openssh/$arch/sshd" ]; then
    ln -sf "../../$ARTIFACTS_DIR/openssh/$arch/sshd" pkg/openssh/sshd
  fi
done

# Build the tree including libc, Leo, and Rust crates
gmake

# Create a minimal LSB root filesystem image
lsb_img="$ARTIFACTS_DIR/images/lsb_root.img"
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
debugfs -w -R "write $ARTIFACTS_DIR/bash/arm64/bash /bin/sh" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0755 /bin/sh" "$lsb_img" >/dev/null
debugfs -w -R "write $ARTIFACTS_DIR/bash/arm64/bash /bin/bash" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0755 /bin/bash" "$lsb_img" >/dev/null

# Set up SSH configuration and host keys
mkdir -p config/lsb_root/etc/ssh
debugfs -w -R "mkdir /etc/ssh" "$lsb_img" >/dev/null
chmod 0644 config/lsb_root/etc/ssh/sshd_config
hostkey_tmp=$(mktemp)
ssh-keygen -t rsa -N '' -f "$hostkey_tmp" >/dev/null
cp "$hostkey_tmp" config/lsb_root/etc/ssh/ssh_host_rsa_key
cp "$hostkey_tmp.pub" config/lsb_root/etc/ssh/ssh_host_rsa_key.pub
chmod 600 config/lsb_root/etc/ssh/ssh_host_rsa_key config/lsb_root/etc/ssh/ssh_host_rsa_key.pub
debugfs -w -R "write config/lsb_root/etc/ssh/sshd_config /etc/ssh/sshd_config" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0644 /etc/ssh/sshd_config" "$lsb_img" >/dev/null
debugfs -w -R "write $hostkey_tmp /etc/ssh/ssh_host_rsa_key" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0600 /etc/ssh/ssh_host_rsa_key" "$lsb_img" >/dev/null
debugfs -w -R "write $hostkey_tmp.pub /etc/ssh/ssh_host_rsa_key.pub" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0600 /etc/ssh/ssh_host_rsa_key.pub" "$lsb_img" >/dev/null
rm "$hostkey_tmp" "$hostkey_tmp.pub"

# Install systemd into the root filesystem image and staging area
sys_root="$ARTIFACTS_DIR/systemd/arm64/root"
if [ -d "$sys_root" ]; then
  mkdir -p config/lsb_root/usr/lib/systemd
  mkdir -p config/lsb_root/lib/systemd
  if [ -d "$sys_root/usr/lib/systemd" ]; then
    cp -r "$sys_root/usr/lib/systemd/"* config/lsb_root/usr/lib/systemd/ 2>/dev/null || true
  fi
  if [ -f "$sys_root/lib/systemd/systemd" ]; then
    cp "$sys_root/lib/systemd/systemd" config/lsb_root/lib/systemd/systemd
    cp "$sys_root/lib/systemd/systemd" config/lsb_root/usr/lib/systemd/systemd
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
units_dir="config/systemd"
if [ -d "$units_dir" ]; then
  mkdir -p config/lsb_root/lib/systemd/system
  debugfs -w -R "mkdir /lib/systemd/system" "$lsb_img" >/dev/null || true
  for unit in "$units_dir"/*.service; do
    [ -f "$unit" ] || continue
    base="$(basename "$unit")"
    cp "$unit" config/lsb_root/lib/systemd/system/
    debugfs -w -R "write $unit /lib/systemd/system/$base" "$lsb_img" >/dev/null
    debugfs -w -R "chmod 0644 /lib/systemd/system/$base" "$lsb_img" >/dev/null
  done
fi

# Enable services
enable_service() {
  local name="$1"
  local unit="config/systemd/${name}.service"
  if [ -f "$unit" ]; then
    mkdir -p config/lsb_root/etc/systemd/system/multi-user.target.wants
    ln -sf ../../../../lib/systemd/system/${name}.service \
      config/lsb_root/etc/systemd/system/multi-user.target.wants/${name}.service
    debugfs -w -R "mkdir /etc/systemd" "$lsb_img" >/dev/null || true
    debugfs -w -R "mkdir /etc/systemd/system" "$lsb_img" >/dev/null || true
    debugfs -w -R "mkdir /etc/systemd/system/multi-user.target.wants" "$lsb_img" >/dev/null || true
    debugfs -w -R "symlink /lib/systemd/system/${name}.service /etc/systemd/system/multi-user.target.wants/${name}.service" "$lsb_img" >/dev/null
  fi
}

enable_service bash
enable_service sshd

# Collect key build artifacts
mkdir -p "$ARTIFACTS_DIR/images"
if [ -f "obj/l4/arm64/images/bootstrap_hello_arm_virt.elf" ]; then
  cp "obj/l4/arm64/images/bootstrap_hello_arm_virt.elf" "$ARTIFACTS_DIR/images/" 2>/dev/null || true
fi
