#!/usr/bin/env bash

# Resolve a path using realpath if available, otherwise fall back to Python.
# We capture the output of realpath first so that a failure (for example when
# the final component does not exist yet) does not trigger `set -e`; instead we
# fall back to Python, which handles such cases portably.
resolve_path() {
  if command -v realpath >/dev/null 2>&1; then
    local resolved
    if resolved=$(realpath "$1" 2>/dev/null); then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi

  python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"
}

# Discover Homebrew tool prefixes on macOS and prepend their bin directories to
# PATH.
setup_macos_paths() {
  if ! command -v brew >/dev/null 2>&1; then
    return
  fi

  local prefix
  local -a formulas=(
    arm-linux-gnueabihf-g++
    aarch64-elf-g++
    e2fsprogs
  )

  local formula
  for formula in "${formulas[@]}"; do
    prefix=$(brew --prefix "$formula" 2>/dev/null) || continue
    PATH="$prefix/bin:$PATH"
  done
  export PATH
}

# Ensure the various CROSS_COMPILE* environment variables stay aligned so that
# the build effectively exposes a single cross-compiler choice. Legacy variables
# still populate CROSS_COMPILE when the shared prefix is absent.
sync_cross_compile_variables() {
  local primary="${CROSS_COMPILE:-}"

  if [ -z "$primary" ]; then
    if [ -n "${CROSS_COMPILE_ARM64:-}" ]; then
      primary="$CROSS_COMPILE_ARM64"
    elif [ -n "${CROSS_COMPILE_ARM:-}" ]; then
      primary="$CROSS_COMPILE_ARM"
    fi
  fi

  CROSS_COMPILE="$primary"
  CROSS_COMPILE_ARM="$primary"
  CROSS_COMPILE_ARM64="$primary"

  export CROSS_COMPILE CROSS_COMPILE_ARM CROSS_COMPILE_ARM64
}

# Locate the prefix for the first available g++ cross-compiler in the list of
# compiler names passed as arguments.
find_gpp_cross_prefix() {
  local compiler
  for compiler in "$@"; do
    if command -v "$compiler" >/dev/null 2>&1; then
      printf '%s' "${compiler%g++}"
      return 0
    fi
  done
  return 1
}

# Detect a single usable cross-compiler prefix and propagate it to the legacy
# variables for compatibility with existing scripts.
detect_cross_compilers() {
  sync_cross_compile_variables

  if [ -n "${CROSS_COMPILE:-}" ]; then
    return
  fi

  case "$(uname -s)" in
    Darwin)
      setup_macos_paths
      local prefix
      if prefix=$(find_gpp_cross_prefix \
        aarch64-elf-g++ \
        aarch64-none-elf-g++ \
        aarch64-linux-gnu-g++ \
        aarch64-unknown-linux-gnu-g++
      ); then
        CROSS_COMPILE="$prefix"
      else
        echo "No AArch64 g++ cross compiler found. Install one via Homebrew (for example, 'brew install aarch64-elf-g++')." >&2
        exit 1
      fi
      ;;
    *)
      CROSS_COMPILE="aarch64-linux-gnu-"
      ;;
  esac

  sync_cross_compile_variables
}
# Verify that all required build tools are available.
validate_tools() {
  local required_tools=(
    git
    gmake
    curl
    rustc
    cargo
    mke2fs
    debugfs
    flex
    bison
    wget
    cmake
    meson
    ninja
    pkg-config
    ham
    "stat|gstat"
    "truncate|gtruncate"
    "timeout|gtimeout|python3"
  )

  if [ -n "${CROSS_COMPILE:-}" ]; then
    required_tools+=("${CROSS_COMPILE}g++")
  fi
  for tool in "${required_tools[@]}"; do
    if [[ "$tool" == *"|"* ]]; then
      IFS="|" read -r -a alts <<<"$tool"
      local found=false
      for alt in "${alts[@]}"; do
        if command -v "$alt" >/dev/null 2>&1; then
          found=true
          break
        fi
      done
      if [ "$found" = false ]; then
        echo "Required tool missing: one of ${alts[*]} is needed" >&2
        exit 1
      fi
    else
      if ! command -v "$tool" >/dev/null 2>&1; then
        if [[ "$tool" == "${CROSS_COMPILE}g++" ]]; then
          echo "Required tool $tool not found (CROSS_COMPILE=${CROSS_COMPILE})" >&2
        elif [[ "$tool" == rustc ]]; then
          echo "Required tool rustc not found. Install a Rust toolchain (e.g., via https://rustup.rs/)." >&2
        elif [[ "$tool" == cargo ]]; then
          echo "Required tool cargo not found. Install a Rust toolchain (e.g., via https://rustup.rs/)." >&2
        elif [[ "$tool" == ham ]]; then
          echo "Required tool ham not found. Install ham and ensure it is in your PATH" >&2
        else
          echo "Required tool $tool not found" >&2
        fi
        exit 1
      fi
    fi
  done

  local make_cmd="gmake"

  local make_version
  make_version=$("$make_cmd" --version 2>/dev/null | head -n 1)
  if [[ $make_version =~ ([0-9]+)\. ]]; then
    local make_major=${BASH_REMATCH[1]}
    if (( make_major < 4 )); then
      echo "gmake >=4 is required. Found $make_version. Install a newer gmake (e.g., 'brew install make' on macOS)." >&2
      exit 1
    fi
  else
    echo "Unable to determine gmake version from '$make_version'" >&2
    exit 1
  fi

  setup_macos_coreutils
}

# Create temporary aliases for GNU coreutils on macOS.
setup_macos_coreutils() {
  if [[ $(uname -s) != "Darwin" || -n "${GNU_COREUTILS_SETUP_DONE:-}" ]]; then
    return
  fi
  GNU_COREUTILS_SETUP_DONE=1

  local alias_dir
  alias_dir=$(mktemp -d)
  for util in stat truncate timeout; do
    local gutil="g${util}"
    if command -v "$gutil" >/dev/null 2>&1; then
      ln -sf "$(command -v "$gutil")" "$alias_dir/$util"
    fi
  done
  PATH="$alias_dir:$PATH"
  export PATH
}

sync_cross_compile_variables

