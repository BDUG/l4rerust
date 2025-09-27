#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"
# shellcheck source=lib/component_artifacts.sh
source "$SCRIPT_DIR/lib/component_artifacts.sh"

read_makefile_var() {
  local var_name="$1"
  local makefile_path="${2:-Makefile}"

  if [ ! -f "$makefile_path" ]; then
    return 0
  fi

  awk -v name="$var_name" -F'=' '
    $1 ~ ("^" name "[\\t ]*$") {
      sub(/^[\\t ]*/, "", $2)
      print $2
      exit
    }
  ' "$makefile_path"
}

sanitize_build_flag() {
  local value="$1"

  printf '%s\n' "$value" |
    sed -e 's/-DCROSS_COMPILING//g' \
        -e 's/-D[[:space:]]\+CROSS_COMPILING//g' \
        -e 's/[[:space:]]\+/ /g' \
        -e 's/^ //; s/ $//'
}

usage() {
  echo "Usage: $0 <arch> <cross-prefix> <expected-version> <artifacts-dir> <source-dir>" >&2
  exit 1
}

main() {
  if [ "$#" -ne 5 ]; then
    usage
  fi

  local arch="$1" cross="$2" expected_version="$3" artifacts_dir="$4" source_dir="$5"

  ARTIFACTS_DIR="$artifacts_dir"
  cd "$REPO_ROOT"

  if [[ "$source_dir" != /* ]]; then
    source_dir="$REPO_ROOT/$source_dir"
  fi

  local triple
  triple="$(${cross}g++ -dumpmachine)"
  if [[ "$triple" != *-linux-* && "$triple" != *-elf* ]]; then
    echo "${cross}g++ targets '$triple', which is neither a Linux nor ELF target" >&2
    exit 1
  fi

  local host="$triple"
  local out_dir="$ARTIFACTS_DIR/bash/$arch"
  local out_dir_path
  if [[ "$out_dir" == /* ]]; then
    out_dir_path="$out_dir"
  else
    out_dir_path="$REPO_ROOT/$out_dir"
  fi

  if component_is_current "bash" "$arch" "bash" "$expected_version"; then
    echo "bash for $arch already current, skipping"
    return 0
  fi

  mkdir -p "$out_dir_path"
  local native_cc
  native_cc="${CC_FOR_BUILD:-${BUILD_CC:-}}"
  if [ -z "$native_cc" ]; then
    if command -v gcc >/dev/null 2>&1; then
      native_cc="gcc"
    else
      native_cc="cc"
    fi
  fi

  (
    cd "$source_dir"
    gmake distclean >/dev/null 2>&1 || true
    CC="${cross}gcc" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" \
    CC_FOR_BUILD="$native_cc" BUILD_CC="$native_cc" \
      ./configure --host="$host" --without-bash-malloc

    local build_cflags_for_build
    local build_cppflags_for_build
    local build_ldflags_for_build

    build_cflags_for_build=$(sanitize_build_flag "$(read_makefile_var "CFLAGS_FOR_BUILD")")
    build_cppflags_for_build=$(sanitize_build_flag "$(read_makefile_var "CPPFLAGS_FOR_BUILD")")
    build_ldflags_for_build=$(sanitize_build_flag "$(read_makefile_var "LDFLAGS_FOR_BUILD")")
    local_defs_for_build=$(sanitize_build_flag "$(read_makefile_var "LOCAL_DEFS_FOR_BUILD")")
    local_defs=$(sanitize_build_flag "$(read_makefile_var "LOCAL_DEFS")")

    CC_FOR_BUILD="$native_cc" BUILD_CC="$native_cc" \
    CFLAGS_FOR_BUILD="$build_cflags_for_build" \
    CPPFLAGS_FOR_BUILD="$build_cppflags_for_build" \
    LDFLAGS_FOR_BUILD="$build_ldflags_for_build" \
    LOCAL_DEFS_FOR_BUILD="$local_defs_for_build" \
    LOCAL_DEFS="$local_defs" \
      gmake clean

    CC="${cross}gcc" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" \
    CC_FOR_BUILD="$native_cc" BUILD_CC="$native_cc" \
    CFLAGS_FOR_BUILD="$build_cflags_for_build" \
    CPPFLAGS_FOR_BUILD="$build_cppflags_for_build" \
    LDFLAGS_FOR_BUILD="$build_ldflags_for_build" \
    LOCAL_DEFS_FOR_BUILD="$local_defs_for_build" \
    LOCAL_DEFS="$local_defs" \
      gmake STATIC_LDFLAGS=-static
    cp bash "$out_dir_path/"
  )
  echo "$expected_version" > "$out_dir_path/VERSION"
}

main "$@"
