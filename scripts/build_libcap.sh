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

  if [[ "$install_prefix" != /* ]]; then
    install_prefix="$REPO_ROOT/$install_prefix"
  fi

  local triple
  triple="$(${cross}g++ -dumpmachine)"

  local microkernel=false
  if [[ "$triple" == *-linux-* ]]; then
    microkernel=false
  elif [[ "$triple" == *-elf-* || "$triple" == *-elf ]]; then
    microkernel=true
  else
    echo "${cross}g++ targets '$triple', but libcap requires a Linux or L4Re ELF toolchain" >&2
    exit 1
  fi

  rm -rf "$install_prefix"
  mkdir -p "$install_prefix"

  local -a make_args=(
    "BUILD_CC=gcc"
    "CC=${cross}gcc"
    "AR=${cross}ar"
    "RANLIB=${cross}ranlib"
    "prefix=$install_prefix"
    "lib=lib"
  )

  if [ "$microkernel" = true ]; then
    make_args+=(
      "KERNEL_HEADERS=$REPO_ROOT/pkg/include"
      "PTHREADS=no"
      "SHARED=no"
    )
  fi

  (
    cd "$src_dir"
    gmake -C libcap "${make_args[@]}" distclean >/dev/null 2>&1 || true
    gmake -C libcap "${make_args[@]}" clean >/dev/null 2>&1 || true
    gmake -C libcap "${make_args[@]}" install
  )

  if [ "$microkernel" = true ]; then
    local shim_header="$REPO_ROOT/pkg/include/linux/capability.h"
    if [ ! -f "$shim_header" ]; then
      echo "Missing capability shim header at $shim_header" >&2
      exit 1
    fi
    mkdir -p "$install_prefix/include/linux"
    cp "$shim_header" "$install_prefix/include/linux/"
  fi

  local pkgconfig_file="$install_prefix/lib/pkgconfig/libcap.pc"
  if [ -f "$pkgconfig_file" ]; then
    local tmp_pc
    tmp_pc=$(mktemp)
    sed "s/^Version:.*/Version: $expected_version/" "$pkgconfig_file" >"$tmp_pc"
    mv "$tmp_pc" "$pkgconfig_file"
  else
    mkdir -p "$install_prefix/lib/pkgconfig"
    cat >"$pkgconfig_file" <<EOF_PC
prefix=$install_prefix
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libcap
Description: POSIX capabilities library
Version: $expected_version
Libs: -L\${libdir} -lcap
Cflags: -I\${includedir}
EOF_PC
  fi

  echo "$expected_version" > "$install_prefix/VERSION"
}

main "$@"
