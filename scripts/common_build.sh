#!/usr/bin/env bash

# Resolve a path using realpath if available, otherwise fall back to Python.
resolve_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"
  fi
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

# Detect suitable cross-compilers for ARM and ARM64.
detect_cross_compilers() {
  if [ -z "${CROSS_COMPILE_ARM:-}" ] || [ -z "${CROSS_COMPILE_ARM64:-}" ]; then
    case "$(uname -s)" in
    Darwin)
      local machine
      machine=$(uname -m)
      setup_macos_paths

      if [ -z "${CROSS_COMPILE_ARM:-}" ]; then
        local prefix
        if prefix=$(find_gpp_cross_prefix arm-linux-gnueabihf-g++); then
          CROSS_COMPILE_ARM="$prefix"
        else
          echo "No Linux-targeted ARM g++ cross compiler found (expected arm-linux-gnueabihf-g++)." \
            "Install it on macOS via Homebrew: 'brew install arm-linux-gnueabihf-g++'." >&2
          exit 1
        fi
      fi

      if [ -z "${CROSS_COMPILE_ARM64:-}" ]; then
        local prefix
        if prefix=$(find_gpp_cross_prefix \
          aarch64-elf-g++ \
          aarch64-none-elf-g++ \
          aarch64-linux-gnu-g++ \
          aarch64-unknown-linux-gnu-g++
        ); then
          CROSS_COMPILE_ARM64="$prefix"
        else
          echo "No AArch64 g++ cross compiler found. Please install aarch64-elf-g++ (preferred; Linux hosts may use aarch64-linux-gnu-g++ or aarch64-unknown-linux-gnu-g++)." >&2
          exit 1
        fi
      fi

      if [[ ${CROSS_COMPILE_ARM64} != *elf* && ${CROSS_COMPILE_ARM64} != *linux* ]]; then
        echo "No ELF- or Linux-targeted AArch64 g++ cross compiler prefix found (expected aarch64-elf- (macOS), aarch64-none-elf-, aarch64-linux-gnu-, or aarch64-unknown-linux-gnu-)." >&2
        exit 1
      fi

      if [[ ${machine} != "arm64" && ${CROSS_COMPILE_ARM} != *linux* ]]; then
        echo "No Linux-targeted ARM g++ cross compiler prefix found (expected arm-linux-gnueabihf-)." >&2
        exit 1
      fi

      ;;
    *)
      CROSS_COMPILE_ARM=${CROSS_COMPILE_ARM:-arm-linux-gnueabihf-}
      CROSS_COMPILE_ARM64=${CROSS_COMPILE_ARM64:-aarch64-linux-gnu-}
      ;;
    esac
  fi
}

# Verify that all required build tools are available.
validate_tools() {
  local required_tools=(
    git
    gmake
    curl
    "${CROSS_COMPILE_ARM}g++"
    "${CROSS_COMPILE_ARM64}g++"
    mke2fs
    debugfs
    ssh-keygen
    cmake
    meson
    ninja
    pkg-config
    ham
    "stat|gstat"
    "truncate|gtruncate"
    "timeout|gtimeout|python3"
  )
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
        if [[ "$tool" == "${CROSS_COMPILE_ARM}g++" ]]; then
          echo "Required tool $tool not found (CROSS_COMPILE_ARM=${CROSS_COMPILE_ARM})" >&2
        elif [[ "$tool" == "${CROSS_COMPILE_ARM64}g++" ]]; then
          echo "Required tool $tool not found (CROSS_COMPILE_ARM64=${CROSS_COMPILE_ARM64})" >&2
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

