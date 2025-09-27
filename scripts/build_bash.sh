#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"
# shellcheck source=lib/component_artifacts.sh
source "$SCRIPT_DIR/lib/component_artifacts.sh"

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
  (
    cd "$source_dir"
    gmake distclean >/dev/null 2>&1 || true
    CC="${cross}gcc" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" \
      ./configure --host="$host" --without-bash-malloc
    gmake clean
    CC="${cross}gcc" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" \
      gmake STATIC_LDFLAGS=-static
    cp bash "$out_dir_path/"
  )
  echo "$expected_version" > "$out_dir_path/VERSION"
}

main "$@"
