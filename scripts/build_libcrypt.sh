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

  local -a configure_args=(
    "--host=$triple"
    "--prefix=$install_prefix"
  )

  local microkernel=false
  if [[ "$triple" == *-elf-* || "$triple" == *-elf ]]; then
    microkernel=true
    configure_args+=("--disable-shared")
  fi

  rm -rf "$install_prefix"
  mkdir -p "$install_prefix"

  (
    cd "$src_dir"
    gmake distclean >/dev/null 2>&1 || true
    gmake clean >/dev/null 2>&1 || true

    export CC="${cross}gcc"
    export AR="${cross}ar"
    export RANLIB="${cross}ranlib"
    export STRIP="${cross}strip"
    if [ "$microkernel" = true ]; then
      export ac_cv_lib_pthread_pthread_create=no
      export ac_cv_header_pthread_h=no
    else
      unset ac_cv_lib_pthread_pthread_create
      unset ac_cv_header_pthread_h
    fi

    ./configure "${configure_args[@]}"
    gmake
    gmake install
  )

  local pkgconfig_dir="$install_prefix/lib/pkgconfig"
  if [ -d "$pkgconfig_dir" ] && [ ! -f "$pkgconfig_dir/libcrypt.pc" ] && [ -f "$pkgconfig_dir/libxcrypt.pc" ]; then
    ln -sf libxcrypt.pc "$pkgconfig_dir/libcrypt.pc"
  fi

  echo "$expected_version" > "$install_prefix/VERSION"
}

main "$@"
