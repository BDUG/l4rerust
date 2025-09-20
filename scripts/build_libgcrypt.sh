#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"
# shellcheck source=lib/component_artifacts.sh
source "$SCRIPT_DIR/lib/component_artifacts.sh"

usage() {
  echo "Usage: $0 <arch> <cross-prefix> <expected-version> <libgpg-error-src-dir> <libgcrypt-src-dir> <install-prefix> <libgpg-error-version>" >&2
  exit 1
}

main() {
  if [ "$#" -ne 7 ]; then
    usage
  fi

  local arch="$1" cross="$2" expected_version="$3" gpg_error_src_dir="$4" libgcrypt_src_dir="$5" install_prefix="$6" libgpg_error_version="$7"

  if [[ "$gpg_error_src_dir" != /* ]]; then
    gpg_error_src_dir="$REPO_ROOT/$gpg_error_src_dir"
  fi
  gpg_error_src_dir="$(resolve_path "$gpg_error_src_dir")"

  if [[ "$libgcrypt_src_dir" != /* ]]; then
    libgcrypt_src_dir="$REPO_ROOT/$libgcrypt_src_dir"
  fi
  libgcrypt_src_dir="$(resolve_path "$libgcrypt_src_dir")"

  if [[ "$install_prefix" != /* ]]; then
    install_prefix="$REPO_ROOT/$install_prefix"
  fi

  local triple
  triple="$(${cross}g++ -dumpmachine)"
  if [[ "$triple" != *-linux-* ]]; then
    echo "${cross}g++ targets '$triple', but libgcrypt for $arch requires a Linux-targeted toolchain" >&2
    exit 1
  fi

  rm -rf "$install_prefix"
  mkdir -p "$install_prefix"

  local build_triple
  build_triple="$(gcc -dumpmachine)"

  (
    cd "$gpg_error_src_dir"
    gmake distclean >/dev/null 2>&1 || true
    gmake clean >/dev/null 2>&1 || true

    export CC="${cross}gcc"
    export AR="${cross}ar"
    export RANLIB="${cross}ranlib"
    export STRIP="${cross}strip"

    ./configure \
      --build="$build_triple" \
      --host="$triple" \
      --prefix="$install_prefix" \
      --disable-doc
    gmake
    gmake install
  )

  (
    cd "$libgcrypt_src_dir"
    gmake distclean >/dev/null 2>&1 || true
    gmake clean >/dev/null 2>&1 || true

    export CC="${cross}gcc"
    export AR="${cross}ar"
    export RANLIB="${cross}ranlib"
    export STRIP="${cross}strip"
    export PKG_CONFIG_PATH="$install_prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

    ./configure \
      --build="$build_triple" \
      --host="$triple" \
      --prefix="$install_prefix" \
      --disable-doc \
      --disable-asm \
      --with-libgpg-error-prefix="$install_prefix"
    gmake
    gmake install
  )

  local pkgconfig_dir="$install_prefix/lib/pkgconfig"
  mkdir -p "$pkgconfig_dir"
  if [ ! -f "$pkgconfig_dir/gpg-error.pc" ]; then
    cat >"$pkgconfig_dir/gpg-error.pc" <<EOF_PC
prefix=$install_prefix
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libgpg-error
Description: Library for error codes used by GnuPG
Version: $libgpg_error_version
Libs: -L\${libdir} -lgpg-error
Cflags: -I\${includedir}
EOF_PC
  fi

  echo "$expected_version" > "$install_prefix/VERSION"
}

main "$@"
