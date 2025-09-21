#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"

GLIBC_BUILD_TMPDIR=""

cleanup_tmpdir() {
  if [[ -n "${GLIBC_BUILD_TMPDIR:-}" && -d "$GLIBC_BUILD_TMPDIR" ]]; then
    rm -rf "$GLIBC_BUILD_TMPDIR"
  fi
}

trap cleanup_tmpdir EXIT

usage() {
  echo "Usage: $0 <arch> <cross-prefix> <expected-version> <install-prefix> <osv-url> <osv-commit> <musl-submodule> <musl-commit>" >&2
  exit 1
}

clone_osv_tree() {
  local dest_dir="$1" url="$2" commit="$3" submodule="$4" submodule_commit="$5"

  git init "$dest_dir" >/dev/null
  git -C "$dest_dir" remote add origin "$url" >/dev/null
  git -C "$dest_dir" fetch --depth 1 origin "$commit" >/dev/null
  git -C "$dest_dir" checkout FETCH_HEAD >/dev/null
  git -C "$dest_dir" submodule update --init --recursive --depth 1 >/dev/null

  if [ ! -d "$dest_dir/$submodule" ]; then
    echo "Expected submodule $submodule not present after checkout" >&2
    return 1
  fi

  local actual_submodule_commit
  actual_submodule_commit=$(git -C "$dest_dir/$submodule" rev-parse HEAD)
  if [ "$actual_submodule_commit" != "$submodule_commit" ]; then
    echo "Submodule $submodule checked out at $actual_submodule_commit, expected $submodule_commit" >&2
    return 1
  fi
}

stage_headers() {
  local osv_dir="$1" dest_prefix="$2"

  rm -rf "$dest_prefix/include"
  mkdir -p "$dest_prefix"
  cp -a "$osv_dir/include/glibc-compat" "$dest_prefix/include"
}

stage_libraries() {
  local build_out="$1" dest_prefix="$2"

  mkdir -p "$dest_prefix/lib"

  local -a libs_to_copy=()
  while IFS= read -r -d '' libfile; do
    libs_to_copy+=("$libfile")
  done < <(find "$build_out" -maxdepth 2 -type f \( -name 'lib*.so' -o -name 'lib*.so.*' -o -name 'ld-*.so*' \) -print0)

  if [ ${#libs_to_copy[@]} -eq 0 ]; then
    echo "No shared libraries were produced in $build_out" >&2
    return 1
  fi

  local libfile
  for libfile in "${libs_to_copy[@]}"; do
    cp -a "$libfile" "$dest_prefix/lib/"
  done
}

ensure_library_symlink() {
  local libdir="$1" base="$2"
  if [ -e "$libdir/$base" ]; then
    return 0
  fi
  local target
  target=$(find "$libdir" -maxdepth 1 -type f -name "$base.*" | sort | head -n1 || true)
  if [ -n "$target" ]; then
    ln -sfn "$(basename "$target")" "$libdir/$base"
  fi
}

stage_pkgconfig() {
  local dest_prefix="$1" version="$2"
  local pc_dir="$dest_prefix/lib/pkgconfig"

  mkdir -p "$pc_dir"
  cat <<PC >"$pc_dir/osv-glibc.pc"
prefix=$dest_prefix
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: osv-glibc
Description: OSv glibc compatibility layer
Version: $version
Libs: -L\${libdir} -lc -lpthread -ldl -lm -lrt -lresolv -lcrypt -lutil
Cflags: -I\${includedir}
PC
  ln -sfn osv-glibc.pc "$pc_dir/glibc.pc"
}

ensure_osv_dependencies() {
  local osv_dir="$1" arch="$2"

  case "$arch" in
    arm64)
      local packages_root="$osv_dir/build/downloaded_packages/aarch64"
      local boost_install="$packages_root/boost/install"
      local gcc_install="$packages_root/gcc/install"
      if [ -d "$boost_install" ] && [ -d "$gcc_install" ]; then
        return 0
      fi

      local download_script="$osv_dir/scripts/download_aarch64_packages.py"
      if [ ! -f "$download_script" ]; then
        echo "Required download script not found: $download_script" >&2
        return 1
      fi

      if ! python3 -c 'import distro' >/dev/null 2>&1; then
        echo "Python module 'distro' is required to download OSv aarch64 packages. Install python3-distro." >&2
        return 1
      fi

      echo "Fetching OSv aarch64 dependency packages..."
      if ! python3 "$download_script"; then
        echo "Failed to download OSv aarch64 dependency packages." >&2
        echo "Ensure python3-distro, wget, and the aarch64 cross compiler toolchain are installed." >&2
        return 1
      fi
      ;;
  esac
}

main() {
  if [ "$#" -ne 8 ]; then
    usage
  fi

  local arch="$1" cross="$2" expected_version="$3" install_prefix="$4"
  local osv_url="$5" osv_commit="$6" musl_submodule="$7" musl_commit="$8"

  if [[ "$install_prefix" != /* ]]; then
    install_prefix="$REPO_ROOT/$install_prefix"
  fi
  install_prefix="$(resolve_path "$install_prefix")"

  GLIBC_BUILD_TMPDIR=$(mktemp -d)

  local osv_dir="$GLIBC_BUILD_TMPDIR/osv"
  mkdir -p "$osv_dir"
  clone_osv_tree "$osv_dir" "$osv_url" "$osv_commit" "$musl_submodule" "$musl_commit"

  local osv_arch
  case "$arch" in
    arm)
      osv_arch="arm"
      ;;
    arm64)
      osv_arch="aarch64"
      ;;
    *)
      echo "Unsupported architecture '$arch'" >&2
      exit 1
      ;;
  esac

  if [ ! -f "$osv_dir/conf/${osv_arch}.mk" ]; then
    echo "OSv sources do not include support for architecture '$arch'" >&2
    exit 3
  fi

  if [ ! -d "$osv_dir/libc" ] || [ ! -d "$osv_dir/include/glibc-compat" ] || [ ! -d "$osv_dir/exported_symbols" ]; then
    echo "OSv sources missing required directories" >&2
    exit 1
  fi

  ensure_osv_dependencies "$osv_dir" "$arch"

  local make_mode="release"
  (
    cd "$osv_dir"
    export CROSS_PREFIX="$cross"
    gmake mode="$make_mode" arch="$osv_arch" stage1
    gmake mode="$make_mode" arch="$osv_arch" loader.elf
  )

  local build_out="$osv_dir/build/${make_mode}.${osv_arch}"
  if [ ! -d "$build_out" ]; then
    echo "OSv build output directory $build_out not found" >&2
    exit 1
  fi

  rm -rf "$install_prefix"
  mkdir -p "$install_prefix"

  stage_headers "$osv_dir" "$install_prefix"
  stage_libraries "$build_out" "$install_prefix"
  local libdir="$install_prefix/lib"
  if [ -d "$libdir" ]; then
    ensure_library_symlink "$libdir" "libc.so"
    ensure_library_symlink "$libdir" "libpthread.so"
    ensure_library_symlink "$libdir" "libdl.so"
    ensure_library_symlink "$libdir" "librt.so"
    ensure_library_symlink "$libdir" "libm.so"
    ensure_library_symlink "$libdir" "libresolv.so"
    ensure_library_symlink "$libdir" "libcrypt.so"
    ensure_library_symlink "$libdir" "libutil.so"
  fi
  stage_pkgconfig "$install_prefix" "$expected_version"

  echo "$expected_version" >"$install_prefix/VERSION"
}

main "$@"
