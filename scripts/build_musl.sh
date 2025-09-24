#!/usr/bin/env bash
set -euo pipefail

build_dir=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"

usage() {
  echo "Usage: $0 <arch> <cross-prefix> <expected-version> <install-prefix> <src-dir>" >&2
  exit 1
}

cleanup() {
  local dir="${build_dir:-}"
  if [ -n "$dir" ]; then
    rm -rf "$dir"
  fi
}

main() {
  if [ "$#" -ne 5 ]; then
    usage
  fi

  local arch="$1" cross_prefix="$2" expected_version="$3" install_prefix="$4" src_dir="$5"

  if [[ "$src_dir" != /* ]]; then
    src_dir="$REPO_ROOT/$src_dir"
  fi
  if [[ "$install_prefix" != /* ]]; then
    install_prefix="$REPO_ROOT/$install_prefix"
  fi

  if [ ! -d "$src_dir" ]; then
    echo "musl source directory '$src_dir' does not exist" >&2
    exit 1
  fi

  local target triplet
  case "$arch" in
    arm)
      target="arm-linux-musleabihf"
      ;;
    arm64)
      target="aarch64-linux-musl"
      ;;
    *)
      echo "Unsupported musl architecture '$arch'" >&2
      exit 1
      ;;
  esac

  triplet="${cross_prefix}gcc"
  if ! command -v "$triplet" >/dev/null 2>&1; then
    echo "Cross compiler '${cross_prefix}gcc' not found" >&2
    exit 1
  fi

  rm -rf "$install_prefix"
  mkdir -p "$install_prefix"

  build_dir=$(mktemp -d "$src_dir/build-${arch}.XXXXXX")
  trap cleanup EXIT

  local jobs=1
  if command -v nproc >/dev/null 2>&1; then
    jobs=$(nproc)
  elif command -v sysctl >/dev/null 2>&1; then
    jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
  fi

  (
    cd "$build_dir"
    "$src_dir/configure" \
      --prefix="$install_prefix" \
      --target="$target" \
      --enable-shared \
      --enable-static \
      CC="${cross_prefix}gcc" \
      AR="${cross_prefix}ar" \
      RANLIB="${cross_prefix}ranlib" \
      STRIP="${cross_prefix}strip"

    make -j"$jobs"
    make install
  )

  mkdir -p "$install_prefix/lib/pkgconfig"
  cat >"$install_prefix/lib/pkgconfig/musl.pc" <<EOF_PC
prefix=$install_prefix
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: musl
Description: musl libc for L4Re
Version: $expected_version
Libs: -L\${libdir} -lc
Cflags: -I\${includedir}
EOF_PC

  ln -sfn musl.pc "$install_prefix/lib/pkgconfig/libc.pc"

  echo "$expected_version" >"$install_prefix/VERSION"
}

main "$@"
