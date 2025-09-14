#!/usr/bin/env bash

# Detect suitable cross-compilers for ARM and ARM64.
detect_cross_compilers() {
  if [ -z "${CROSS_COMPILE_ARM:-}" ] || [ -z "${CROSS_COMPILE_ARM64:-}" ]; then
    case "$(uname -s)" in
    Darwin)
      local machine
      machine=$(uname -m)

      if [ -z "${CROSS_COMPILE_ARM:-}" ]; then
        if command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
          CROSS_COMPILE_ARM=arm-linux-gnueabihf-
        else
          CROSS_COMPILE_ARM=arm-none-eabi-
        fi
      fi

      if [ -z "${CROSS_COMPILE_ARM64:-}" ]; then
        if command -v aarch64-elf-gcc >/dev/null 2>&1; then
          CROSS_COMPILE_ARM64=aarch64-elf-
        elif command -v aarch64-none-elf-gcc >/dev/null 2>&1; then
          CROSS_COMPILE_ARM64=aarch64-none-elf-
        elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
          CROSS_COMPILE_ARM64=aarch64-linux-gnu-
        elif command -v aarch64-unknown-linux-gnu-gcc >/dev/null 2>&1; then
          CROSS_COMPILE_ARM64=aarch64-unknown-linux-gnu-
        else
          echo "No AArch64 cross compiler found. Please install aarch64-elf-gcc (preferred; Linux hosts may use aarch64-linux-gnu-gcc or aarch64-unknown-linux-gnu-gcc)." >&2
          exit 1
        fi
      fi

      if [[ ${CROSS_COMPILE_ARM64} != *elf* && ${CROSS_COMPILE_ARM64} != *linux* ]]; then
        echo "No ELF- or Linux-targeted AArch64 cross compiler found (expected aarch64-elf- (macOS), aarch64-none-elf-, aarch64-linux-gnu-, or aarch64-unknown-linux-gnu-)." >&2
        exit 1
      fi

      if [[ ${machine} != "arm64" && ${CROSS_COMPILE_ARM} != *linux* ]]; then
        echo "No Linux-targeted ARM cross compiler found (expected arm-linux-gnueabihf-)." >&2
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
    ham
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
        if [[ "$tool" == "${CROSS_COMPILE_ARM}gcc" ]]; then
          echo "Required tool $tool not found (CROSS_COMPILE_ARM=${CROSS_COMPILE_ARM})" >&2
        elif [[ "$tool" == "${CROSS_COMPILE_ARM64}gcc" ]]; then
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
}

