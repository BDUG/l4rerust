#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"
# shellcheck source=lib/component_artifacts.sh
source "$SCRIPT_DIR/lib/component_artifacts.sh"

usage() {
  echo "Usage: $0 <arch> <cross-prefix> <expected-version> <source-dir> <install-prefix>" >&2
  exit 1
}

main() {
  if [ "$#" -ne 5 ]; then
    usage
  fi

  local arch="$1" cross="$2" expected_version="$3" src_dir="$4" install_prefix="$5"

  if [[ "$src_dir" != /* ]]; then
    src_dir="$REPO_ROOT/$src_dir"
  fi
  src_dir="$(resolve_path "$src_dir")"

  if [[ "$install_prefix" != /* ]]; then
    install_prefix="$REPO_ROOT/$install_prefix"
  fi

  local triple
  triple="$(${cross}g++ -dumpmachine)"
  if [[ "$triple" != *-linux-* && "$triple" != *-elf* ]]; then
    echo "${cross}g++ targets '$triple', which is neither a Linux nor ELF target" >&2
    exit 1
  fi

  rm -rf "$install_prefix"
  mkdir -p "$install_prefix"

  (
    cd "$src_dir"
    gmake -C lib distclean >/dev/null 2>&1 || true
    gmake -C lib clean >/dev/null 2>&1 || true
    gmake -C lib \
      CC="${cross}gcc" \
      AR="${cross}ar" \
      RANLIB="${cross}ranlib" \
      PREFIX="$install_prefix" \
      libzstd
    gmake -C lib \
      CC="${cross}gcc" \
      AR="${cross}ar" \
      RANLIB="${cross}ranlib" \
      PREFIX="$install_prefix" \
      install
  )

  local pkgconfig_file="$install_prefix/lib/pkgconfig/libzstd.pc"
  if [ ! -f "$pkgconfig_file" ]; then
    mkdir -p "$(dirname "$pkgconfig_file")"
    cat >"$pkgconfig_file" <<EOF_PC
prefix=$install_prefix
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libzstd
Description: Zstandard compression library
Version: $expected_version
Libs: -L\${libdir} -lzstd
Cflags: -I\${includedir}
EOF_PC
  fi

  echo "$expected_version" > "$install_prefix/VERSION"
}

main "$@"
