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

determine_minimal_musl_objects() {
  local nm_bin="$1"
  local archive="$2"
  shift 2 || true
  local symbols=("$@")

  python3 - "$nm_bin" "$archive" "${symbols[@]}" <<'PY'
import os
import subprocess
import sys

nm = sys.argv[1]
archive = sys.argv[2]
raw_symbols = sys.argv[3:]
symbols = []
for raw in raw_symbols:
    optional = raw.endswith("?")
    name = raw[:-1] if optional else raw
    symbols.append((name, optional))

try:
    proc = subprocess.run(
        [nm, "-g", "--defined-only", archive],
        check=True,
        text=True,
        capture_output=True,
    )
except FileNotFoundError:
    print(f"nm binary '{nm}' not found", file=sys.stderr)
    sys.exit(1)

current_obj = None
mapping = {}
for line in proc.stdout.splitlines():
    if not line:
        continue
    if line.endswith(":"):
        current_obj = line[:-1].strip()
        if current_obj.startswith(archive):
            current_obj = os.path.basename(current_obj)
        continue
    if current_obj is None:
        continue
    parts = line.split()
    if len(parts) < 3:
        continue
    symbol_type = parts[-2].upper()
    symbol = parts[-1]
    if symbol_type in {"T", "D", "B", "W"}:
        mapping.setdefault(symbol, current_obj)

missing = [name for name, optional in symbols if not optional and name not in mapping]
if missing:
    for sym in missing:
        print(f"Missing symbol {sym} in {archive}", file=sys.stderr)
    sys.exit(1)

seen = set()
for name, optional in symbols:
    obj = mapping.get(name)
    if obj is None:
        if optional:
            continue
        raise RuntimeError(f"Symbol {name} unexpectedly missing")
    if obj not in seen:
        seen.add(obj)
        print(obj)
PY
}

minimise_musl_libc() {
  local install_prefix="$1"
  local cross_prefix="$2"

  local lib_dir="$install_prefix/lib"
  local libc_archive="$lib_dir/libc.a"
  if [ ! -f "$libc_archive" ]; then
    echo "musl archive not found at $libc_archive" >&2
    return 1
  fi

  local nm_bin="${cross_prefix}nm"
  if ! command -v "$nm_bin" >/dev/null 2>&1; then
    if command -v nm >/dev/null 2>&1; then
      nm_bin="nm"
    else
      echo "No suitable nm binary found for prefix '$cross_prefix'" >&2
      return 1
    fi
  fi

  local ar_bin="${cross_prefix}ar"
  if ! command -v "$ar_bin" >/dev/null 2>&1; then
    if command -v ar >/dev/null 2>&1; then
      ar_bin="ar"
    else
      echo "No suitable ar binary found for prefix '$cross_prefix'" >&2
      return 1
    fi
  fi

  local -a required_symbols=(
    eventfd
    eventfd_read
    eventfd_write
    epoll_create
    epoll_create1
    epoll_ctl
    epoll_wait
    epoll_pwait
    nanosleep
    signalfd
    signalfd4?
    timerfd_create
    timerfd_settime
    timerfd_gettime
    inotify_init1
    inotify_add_watch
    inotify_rm_watch
    __syscall
    __syscall_cp
    __syscall_ret
    __block_all_sigs
    __restore_sigs
    __pthread_self
    pthread_testcancel
    libc
  )

  local objects
  if ! objects=$(determine_minimal_musl_objects "$nm_bin" "$libc_archive" "${required_symbols[@]}"); then
    echo "Failed to determine musl object set for L4Re shims" >&2
    return 1
  fi

  if [ -z "$objects" ]; then
    echo "No musl objects identified for minimal archive" >&2
    return 1
  fi

  local tmpdir
  tmpdir=$(mktemp -d "$lib_dir/libc-minimal.XXXXXX")
  trap 'rm -rf "$tmpdir"' RETURN

  local backup_archive="$lib_dir/libc.full.a"
  rm -f "$backup_archive"
  mv "$libc_archive" "$backup_archive"

  printf '%s\n' "$objects" >"$tmpdir/objects.list"

  if ! (
    cd "$tmpdir" &&
      obj_list=() &&
      while IFS= read -r object; do
        [ -n "$object" ] || continue
        obj_list+=("$object")
        "$ar_bin" x "$backup_archive" "$object"
      done <"objects.list" &&
      "$ar_bin" crs "$libc_archive" "${obj_list[@]}"
  ); then
    mv "$backup_archive" "$libc_archive"
    rm -rf "$tmpdir"
    trap - RETURN
    return 1
  fi

  if [ -f "$lib_dir/libc.so" ]; then
    mv "$lib_dir/libc.so" "$lib_dir/libc.full.so"
  fi

  if ls "$lib_dir"/ld-musl-*.so.1 >/dev/null 2>&1; then
    for loader in "$lib_dir"/ld-musl-*.so.1; do
      mv "$loader" "$loader.full"
    done
  fi

  rm -rf "$tmpdir"
  trap - RETURN
  echo "Minimised musl libc archive to event/epoll/signalfd/timerfd/inotify/nanosleep symbols"
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

  minimise_musl_libc "$install_prefix" "$cross_prefix"

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
