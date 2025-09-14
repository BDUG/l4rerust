#!/usr/bin/env bash

# Detect suitable cross-compilers for ARM and ARM64.
detect_cross_compilers() {
  if [ -z "${CROSS_COMPILE_ARM:-}" ] || [ -z "${CROSS_COMPILE_ARM64:-}" ]; then
    case "$(uname -s)" in
    Darwin)
      CROSS_COMPILE_ARM=${CROSS_COMPILE_ARM:-arm-none-eabi-}
      if [ -z "${CROSS_COMPILE_ARM64:-}" ]; then
        if command -v aarch64-unknown-linux-gnu-gcc >/dev/null 2>&1; then
          CROSS_COMPILE_ARM64=aarch64-unknown-linux-gnu-
        else
          CROSS_COMPILE_ARM64=aarch64-none-elf-
        fi
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
    make
    curl
    "${CROSS_COMPILE_ARM}gcc"
    "${CROSS_COMPILE_ARM64}gcc"
    mke2fs
    debugfs
    ssh-keygen
    meson
    ninja
    pkg-config
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
        echo "Required tool $tool not found" >&2
        exit 1
      fi
    fi
  done
}

