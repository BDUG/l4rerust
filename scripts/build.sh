#!/usr/bin/env bash
set -euo pipefail

declare -A SHOULD_BUILD=()
declare -A BUILD_RESULTS=()
declare -A BUILD_NOTES=()
declare -a FAILED_COMPONENTS=()
BUILD_FAILURE_COUNT=0
COMPONENT_BUILD_NOTE=""

print_component_summary() {
  local component
  local result
  local note

  echo
  echo "External component build summary:"
  printf '  %-12s | %-8s | %s\n' "Component" "Result" "Details"
  printf '  %-12s-+-%-8s-+-%s\n' "------------" "--------" "------------------------------"
  for component in "${BUILD_COMPONENT_IDS[@]}"; do
    result="${BUILD_RESULTS[$component]:-not run}"
    note="${BUILD_NOTES[$component]:-}"
    printf '  %-12s | %-8s | %s\n' "$component" "$result" "$note"
  done
}

on_exit() {
  local exit_status=$?
  trap - EXIT
  print_component_summary
  echo "Leaving build container"
  if (( BUILD_FAILURE_COUNT > 0 )); then
    exit 1
  fi
  exit $exit_status
}

echo "Entering build container"
trap on_exit EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"
# shellcheck source=lib/component_artifacts.sh
source "$SCRIPT_DIR/lib/component_artifacts.sh"
cd "$REPO_ROOT"

# Usage: build.sh [options]
#   --clean                    Remove previous build directories before building
#   --no-clean                 Skip removal of build directories (default)
#   --components=name1,name2   Limit builds to the specified components
#   --no-menu                  Skip the interactive component selection menu
#   --help                     Show usage information and exit

readonly -a BUILD_COMPONENT_IDS=(
  bash
  glibc
  libcap
  libcrypt
  libblkid
  libgcrypt
  libzstd
  systemd
  lsb_root
)

declare -A BUILD_COMPONENT_LABELS=(
  [bash]="GNU Bash shell"
  [glibc]="OSv glibc compatibility layer"
  [libcap]="libcap (POSIX capabilities)"
  [libcrypt]="libxcrypt (libcrypt)"
  [libblkid]="util-linux libblkid"
  [libgcrypt]="libgcrypt (and libgpg-error)"
  [libzstd]="Zstandard compression library"
  [systemd]="systemd"
  [lsb_root]="LSB root filesystem creation"
)

run_component_build() {
  local component="$1"
  local func="$2"
  local previous_errexit
  local status
  local note=""

  if ! should_build_component "$component"; then
    echo "Skipping ${component} build (component disabled)"
    BUILD_RESULTS["$component"]="skipped"
    BUILD_NOTES["$component"]="not selected"
    return 0
  fi

  previous_errexit=$(set +o | grep errexit)
  set +e
  COMPONENT_BUILD_NOTE=""
  "$func"
  status=$?
  eval "$previous_errexit"

  note="${COMPONENT_BUILD_NOTE:-}"

  case $status in
    0)
      BUILD_RESULTS["$component"]="success"
      BUILD_NOTES["$component"]="${note:-built}"
      ;;
    2)
      BUILD_RESULTS["$component"]="skipped"
      BUILD_NOTES["$component"]="${note:-skipped}"
      ;;
    *)
      BUILD_RESULTS["$component"]="failed"
      BUILD_NOTES["$component"]="${note:-error}"
      FAILED_COMPONENTS+=("$component")
      BUILD_FAILURE_COUNT=$((BUILD_FAILURE_COUNT + 1))
      ;;
  esac

  return 0
}

usage() {
  cat <<EOF
Usage: $0 [options]
  --clean                    Remove previous build directories before building
  --no-clean                 Skip removal of build directories (default)
  --components=name1,name2   Limit builds to the specified components
  --no-menu                  Skip the interactive component selection menu
  --help                     Show this message and exit
EOF
  local components_list
  components_list=$(IFS=,; echo "${BUILD_COMPONENT_IDS[*]}")
  echo "  Available components: ${components_list}"
  echo
  echo "  The interactive menu also offers an option to clean the build"
  echo "  directories before starting."
}

is_valid_component() {
  local candidate="$1" component
  for component in "${BUILD_COMPONENT_IDS[@]}"; do
    if [ "$component" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

clear_component_selection() {
  local component
  for component in "${BUILD_COMPONENT_IDS[@]}"; do
    SHOULD_BUILD["$component"]=0
  done
}

set_all_components_selected() {
  local component
  for component in "${BUILD_COMPONENT_IDS[@]}"; do
    SHOULD_BUILD["$component"]=1
  done
}

should_build_component() {
  local component="$1"
  [[ "${SHOULD_BUILD["$component"]:-0}" == 1 ]]
}

prompt_component_selection() {
  local -n _result=$1
  _result=()

  if [ ! -t 0 ]; then
    return 1
  fi

  if ! command -v dialog >/dev/null 2>&1; then
    return 1
  fi

  local tmpfile
  tmpfile=$(mktemp)
  local dialog_status=0

  local menu_args=()
  local component
  for component in "${BUILD_COMPONENT_IDS[@]}"; do
    menu_args+=("$component" "${BUILD_COMPONENT_LABELS[$component]}" on)
  done

  if ! dialog --clear \
      --checklist "Select components to build:" 20 70 ${#BUILD_COMPONENT_IDS[@]} \
      "${menu_args[@]}" 2>"$tmpfile"; then
    dialog_status=$?
  fi

  local result
  result=$(<"$tmpfile")
  rm -f "$tmpfile"

  if [ $dialog_status -ne 0 ]; then
    return 1
  fi

  if [ -z "$result" ]; then
    return 1
  fi

  local entry
  for entry in $result; do
    if [[ ${entry:0:1} != '"' ]]; then
      entry="\"$entry\""
    fi
    entry="${entry%\"}"
    entry="${entry#\"}"
    if [ -n "$entry" ]; then
      _result+=("$entry")
    fi
  done

  if [ ${#_result[@]} -eq 0 ]; then
    return 1
  fi

  return 0
}

prompt_clean_before_build() {
  local -n _result=$1
  _result=false

  if [ ! -t 0 ]; then
    return 1
  fi

  if ! command -v dialog >/dev/null 2>&1; then
    return 1
  fi

  local dialog_status=0
  if dialog --clear \
      --yesno "Clean out directory before build?" 7 60; then
    _result=true
  else
    dialog_status=$?
    case $dialog_status in
      1)
        _result=false
        ;;
      *)
        return 1
        ;;
    esac
  fi

  return 0
}

clean=false
component_arg=""
component_arg_set=false
show_menu=true
clean_cli_override=""
menu_clean_requested=false
used_dialog_menu=false
declare -a selected_components=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      clean_cli_override="clean"
      shift
      ;;
    --no-clean)
      clean_cli_override="no-clean"
      shift
      ;;
    --components=*)
      component_arg="${1#--components=}"
      component_arg_set=true
      show_menu=false
      shift
      ;;
    --components)
      if [[ $# -lt 2 ]]; then
        echo "Error: --components requires a comma-separated list" >&2
        usage >&2
        exit 1
      fi
      component_arg="$2"
      component_arg_set=true
      show_menu=false
      shift 2
      ;;
    --no-menu)
      show_menu=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [ "$component_arg_set" = true ]; then
  IFS=',' read -ra selected_components <<< "$component_arg"
  declare -a sanitized_components=()
  declare -A seen_components=()
  component=""
  for component in "${selected_components[@]}"; do
    component="${component//[[:space:]]/}"
    if [ -z "$component" ]; then
      continue
    fi
    if ! is_valid_component "$component"; then
      echo "Unknown component '$component'." >&2
      usage >&2
      exit 1
    fi
    if [[ -n "${seen_components["$component"]-}" ]]; then
      continue
    fi
    sanitized_components+=("$component")
    seen_components["$component"]=1
  done
  if [ ${#sanitized_components[@]} -eq 0 ]; then
    echo "No valid components specified for --components" >&2
    usage >&2
    exit 1
  fi
  selected_components=("${sanitized_components[@]}")
else
  if [ "$show_menu" = true ]; then
    if [ -t 0 ] && command -v dialog >/dev/null 2>&1; then
      if prompt_component_selection selected_components; then
        used_dialog_menu=true
      else
        echo "No components selected; exiting." >&2
        exit 1
      fi
    fi
  fi
fi

if [ "${used_dialog_menu:-false}" = true ]; then
  if prompt_clean_before_build menu_clean_requested; then
    :
  else
    echo "Cleanup selection cancelled; exiting." >&2
    exit 1
  fi
fi

if [ ${#selected_components[@]} -eq 0 ]; then
  selected_components=("${BUILD_COMPONENT_IDS[@]}")
fi

clear_component_selection
if [ ${#selected_components[@]} -eq 0 ]; then
  set_all_components_selected
else
  for component in "${selected_components[@]}"; do
    SHOULD_BUILD["$component"]=1
  done
fi

if [ "$clean_cli_override" = "no-clean" ]; then
  clean=false
elif [ "$clean_cli_override" = "clean" ]; then
  clean=true
elif [ "$menu_clean_requested" = true ]; then
  clean=true
else
  clean=false
fi

if [ "$clean" = true ]; then
  echo "Cleanup before build: enabled"
else
  echo "Cleanup before build: disabled"
fi

echo "Components selected for build: ${selected_components[*]}"

# Set up the L4Re environment (l4re-core and ham)
"$SCRIPT_DIR/setup_l4re_env.sh"
HAM_BIN="$(resolve_path "$SCRIPT_DIR/../ham/ham")"

# Use ham to keep the manifest consistent with the latest l4re-core
(
  cd "$REPO_ROOT/src" &&
  "$HAM_BIN" init -u https://github.com/kernkonzept/manifest.git &&
  "$HAM_BIN" sync 
)

detect_cross_compilers
validate_tools

ARTIFACTS_DIR="out"
export ARTIFACTS_DIR

# Start from a clean state if requested
if [ "$clean" = true ]; then
  echo "Cleaning previous build directories..."
  "$SCRIPT_DIR/setup.sh" clean
else
  echo "Skipping cleanup of previous build directories."
fi

mkdir -p "$ARTIFACTS_DIR"

initialize_component_prefixes

# Configure for ARM using setup script
export CROSS_COMPILE_ARM CROSS_COMPILE_ARM64
# Run the setup tool. If a pre-generated configuration is available, reuse it
# to avoid the interactive `config` step.
if [ -f "$SCRIPT_DIR/l4re.config" ]; then
  echo "Using configuration from scripts/l4re.config"
  mkdir -p obj
  cp "$SCRIPT_DIR/l4re.config" obj/.config
else
  "$SCRIPT_DIR/setup.sh" config
fi
"$SCRIPT_DIR/setup.sh" --non-interactive

# Build the Rust libc crate so other crates can link against it
cargo build -p l4re-libc --release
# Ensure Rust crates pick up the freshly built static libc
export LIBRARY_PATH="$(pwd)/target/release:${LIBRARY_PATH:-}"

BASH_VERSION=5.2.21
BASH_URL="https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz"

LIBCAP_VERSION=2.69
LIBCAP_URL="https://git.kernel.org/pub/scm/libs/libcap/libcap.git/snapshot/libcap-${LIBCAP_VERSION}.tar.gz"

LIBXCRYPT_VERSION=4.4.36
LIBXCRYPT_URL="https://github.com/besser82/libxcrypt/releases/download/v${LIBXCRYPT_VERSION}/libxcrypt-${LIBXCRYPT_VERSION}.tar.xz"

UTIL_LINUX_VERSION=2.39.3
UTIL_LINUX_MAJOR_MINOR="${UTIL_LINUX_VERSION%.*}"
UTIL_LINUX_URL="https://cdn.kernel.org/pub/linux/utils/util-linux/v${UTIL_LINUX_MAJOR_MINOR}/util-linux-${UTIL_LINUX_VERSION}.tar.xz"

LIBGPG_ERROR_VERSION=1.49
LIBGPG_ERROR_URL="https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-${LIBGPG_ERROR_VERSION}.tar.bz2"
LIBGCRYPT_VERSION=1.10.3
LIBGCRYPT_VERSION_MARKER="${LIBGCRYPT_VERSION} (libgpg-error ${LIBGPG_ERROR_VERSION})"
LIBGCRYPT_URL="https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-${LIBGCRYPT_VERSION}.tar.bz2"

LIBZSTD_VERSION=1.5.6
LIBZSTD_URL="https://github.com/facebook/zstd/releases/download/v${LIBZSTD_VERSION}/zstd-${LIBZSTD_VERSION}.tar.gz"

GLIBC_OSV_COMMIT=fe48bcd9065ac625a54aef7b6c46fe70db8fcf7f
GLIBC_OSV_URL="https://github.com/cloudius-systems/osv.git"
GLIBC_MUSL_SUBMODULE="musl_1.1.24"
GLIBC_MUSL_COMMIT=ea9525c8bcf6170df59364c4bcd616de1acf8703
GLIBC_VERSION="$GLIBC_OSV_COMMIT"

build_glibc_component() {
  set -e
  local arch
  local need_glibc=false
  local override_used=false
  local cross=""
  local install_prefix=""
  local build_status=0
  local unsupported_arches=()

  for arch in arm arm64; do
    if component_override_used "glibc" "$arch"; then
      override_used=true
      continue
    fi
    if ! component_is_current "glibc" "$arch" "lib/libc.so" "$GLIBC_VERSION"; then
      need_glibc=true
      break
    fi
  done

  if [ "$need_glibc" = true ]; then
    for arch in arm arm64; do
      if component_override_used "glibc" "$arch"; then
        echo "Skipping glibc build for $arch; using prebuilt artifacts from $(component_prefix_path "glibc" "$arch")"
        continue
      fi
      if component_is_current "glibc" "$arch" "lib/libc.so" "$GLIBC_VERSION"; then
        echo "glibc for $arch already current, skipping"
        continue
      fi

      case "$arch" in
        arm)
          cross="$CROSS_COMPILE_ARM"
          ;;
        arm64)
          cross="$CROSS_COMPILE_ARM64"
          ;;
        *)
          echo "Unsupported architecture '$arch' for glibc build" >&2
          COMPONENT_BUILD_NOTE="unsupported architecture"
          return 1
          ;;
      esac

      install_prefix="$(component_prefix_path "glibc" "$arch")"

      if ! "$SCRIPT_DIR/build_glibc.sh" \
          "$arch" \
          "$cross" \
          "$GLIBC_VERSION" \
          "$install_prefix" \
          "$GLIBC_OSV_URL" \
          "$GLIBC_OSV_COMMIT" \
          "$GLIBC_MUSL_SUBMODULE" \
          "$GLIBC_MUSL_COMMIT"; then
        build_status=$?
        if [ $build_status -eq 3 ]; then
          unsupported_arches+=("$arch")
          continue
        fi
        COMPONENT_BUILD_NOTE="build failed"
        return 1
      fi
    done

    if [ ${#unsupported_arches[@]} -gt 0 ]; then
      echo "glibc build unsupported for: ${unsupported_arches[*]}" >&2
      COMPONENT_BUILD_NOTE="unsupported: ${unsupported_arches[*]}"
      return 1
    fi

    COMPONENT_BUILD_NOTE="built"
    return 0
  fi

  if [ "$override_used" = true ]; then
    echo "glibc builds provided by environment overrides"
    COMPONENT_BUILD_NOTE="overridden"
  else
    echo "glibc for arm and arm64 already current, skipping"
    COMPONENT_BUILD_NOTE="already current"
  fi
  return 2
}

build_bash_component() {
  set -e
  local arch
  local need_bash=false
  local bash_src_dir=""
  local bash_patch_dir=""
  local patch_file

  for arch in arm arm64; do
    if ! component_is_current "bash" "$arch" "bash" "$BASH_VERSION"; then
      need_bash=true
      break
    fi
  done

  if [ "$need_bash" = true ]; then
    bash_src_dir=$(mktemp -d src/bash-XXXXXX)
    curl -L "$BASH_URL" | tar -xz -C "$bash_src_dir" --strip-components=1
    bash_patch_dir="$SCRIPT_DIR/patches/bash"
    if [ -d "$bash_patch_dir" ]; then
      (
        cd "$bash_src_dir"
        for patch_file in "$bash_patch_dir"/*.patch; do
          [ -e "$patch_file" ] || continue
          patch -p1 -N < "$patch_file"
        done
      )
    fi
    "$SCRIPT_DIR/build_bash.sh" arm "$CROSS_COMPILE_ARM" "$BASH_VERSION" "$ARTIFACTS_DIR" "$bash_src_dir"
    "$SCRIPT_DIR/build_bash.sh" arm64 "$CROSS_COMPILE_ARM64" "$BASH_VERSION" "$ARTIFACTS_DIR" "$bash_src_dir"
    rm -rf "$bash_src_dir"
    COMPONENT_BUILD_NOTE="built"
    return 0
  fi

  echo "bash for arm and arm64 already current, skipping"
  COMPONENT_BUILD_NOTE="already current"
  return 2
}

build_libcap_component() {
  set -e
  local arch
  local need_libcap=false
  local override_used=false
  local libcap_src_dir=""
  local cross=""
  local install_prefix=""

  for arch in arm arm64; do
    if component_override_used "libcap" "$arch"; then
      override_used=true
      continue
    fi
    if ! component_is_current "libcap" "$arch" "lib/pkgconfig/libcap.pc" "$LIBCAP_VERSION"; then
      need_libcap=true
      break
    fi
  done

  if [ "$need_libcap" = true ]; then
    libcap_src_dir=$(mktemp -d src/libcap-XXXXXX)
    curl -L "$LIBCAP_URL" | tar -xz -C "$libcap_src_dir" --strip-components=1
    for arch in arm arm64; do
      case "$arch" in
        arm)
          cross="$CROSS_COMPILE_ARM"
          ;;
        arm64)
          cross="$CROSS_COMPILE_ARM64"
          ;;
        *)
          echo "Unsupported architecture '$arch' for libcap build" >&2
          rm -rf "$libcap_src_dir"
          COMPONENT_BUILD_NOTE="unsupported architecture"
          return 1
          ;;
      esac
      if component_override_used "libcap" "$arch"; then
        echo "Skipping libcap build for $arch; using prebuilt artifacts from $(component_prefix_path "libcap" "$arch")"
        continue
      fi
      if component_is_current "libcap" "$arch" "lib/pkgconfig/libcap.pc" "$LIBCAP_VERSION"; then
        echo "libcap for $arch already current, skipping"
        continue
      fi
      install_prefix="$(component_prefix_path "libcap" "$arch")"
      "$SCRIPT_DIR/build_libcap.sh" "$arch" "$cross" "$LIBCAP_VERSION" "$libcap_src_dir" "$install_prefix"
    done
    rm -rf "$libcap_src_dir"
    COMPONENT_BUILD_NOTE="built"
    return 0
  fi

  if [ "$override_used" = true ]; then
    echo "libcap builds provided by environment overrides"
    COMPONENT_BUILD_NOTE="overridden"
  else
    echo "libcap for arm and arm64 already current, skipping"
    COMPONENT_BUILD_NOTE="already current"
  fi
  return 2
}

build_libcrypt_component() {
  set -e
  local arch
  local need_libcrypt=false
  local override_used=false
  local libxcrypt_src_dir=""
  local cross=""
  local install_prefix=""

  for arch in arm arm64; do
    if component_override_used "libcrypt" "$arch"; then
      override_used=true
      continue
    fi
    if ! component_is_current "libcrypt" "$arch" "lib/pkgconfig/libcrypt.pc" "$LIBXCRYPT_VERSION"; then
      need_libcrypt=true
      break
    fi
  done

  if [ "$need_libcrypt" = true ]; then
    libxcrypt_src_dir=$(mktemp -d src/libxcrypt-XXXXXX)
    curl -L "$LIBXCRYPT_URL" | tar -xJ -C "$libxcrypt_src_dir" --strip-components=1
    for arch in arm arm64; do
      if component_override_used "libcrypt" "$arch"; then
        echo "Skipping libcrypt build for $arch; using prebuilt artifacts from $(component_prefix_path "libcrypt" "$arch")"
        continue
      fi
      if component_is_current "libcrypt" "$arch" "lib/pkgconfig/libcrypt.pc" "$LIBXCRYPT_VERSION"; then
        echo "libcrypt for $arch already current, skipping"
        continue
      fi
      case "$arch" in
        arm)
          cross="$CROSS_COMPILE_ARM"
          ;;
        arm64)
          cross="$CROSS_COMPILE_ARM64"
          ;;
        *)
          echo "Unsupported architecture '$arch' for libcrypt build" >&2
          rm -rf "$libxcrypt_src_dir"
          COMPONENT_BUILD_NOTE="unsupported architecture"
          return 1
          ;;
      esac
      install_prefix="$(component_prefix_path "libcrypt" "$arch")"
      "$SCRIPT_DIR/build_libcrypt.sh" "$arch" "$cross" "$LIBXCRYPT_VERSION" "$libxcrypt_src_dir" "$install_prefix"
    done
    rm -rf "$libxcrypt_src_dir"
    COMPONENT_BUILD_NOTE="built"
    return 0
  fi

  if [ "$override_used" = true ]; then
    echo "libcrypt builds provided by environment overrides"
    COMPONENT_BUILD_NOTE="overridden"
  else
    echo "libcrypt for arm and arm64 already current, skipping"
    COMPONENT_BUILD_NOTE="already current"
  fi
  return 2
}

build_libblkid_component() {
  set -e
  local arch
  local need_libblkid=false
  local override_used=false
  local util_linux_src_dir=""
  local cross=""
  local install_prefix=""

  for arch in arm arm64; do
    if component_override_used "libblkid" "$arch"; then
      override_used=true
      continue
    fi
    if ! component_is_current "libblkid" "$arch" "lib/pkgconfig/blkid.pc" "$UTIL_LINUX_VERSION"; then
      need_libblkid=true
      break
    fi
  done

  if [ "$need_libblkid" = true ]; then
    util_linux_src_dir=$(mktemp -d src/util-linux-XXXXXX)
    curl -L "$UTIL_LINUX_URL" | tar -xJ -C "$util_linux_src_dir" --strip-components=1
    for arch in arm arm64; do
      if component_override_used "libblkid" "$arch"; then
        echo "Skipping libblkid build for $arch; using prebuilt artifacts from $(component_prefix_path "libblkid" "$arch")"
        continue
      fi
      if component_is_current "libblkid" "$arch" "lib/pkgconfig/blkid.pc" "$UTIL_LINUX_VERSION"; then
        echo "libblkid for $arch already current, skipping"
        continue
      fi

      case "$arch" in
        arm)
          cross="$CROSS_COMPILE_ARM"
          ;;
        arm64)
          cross="$CROSS_COMPILE_ARM64"
          ;;
        *)
          echo "Unsupported architecture '$arch' for libblkid build" >&2
          rm -rf "$util_linux_src_dir"
          COMPONENT_BUILD_NOTE="unsupported architecture"
          return 1
          ;;
      esac

      install_prefix="$(component_prefix_path "libblkid" "$arch")"
      "$SCRIPT_DIR/build_libblkid.sh" "$arch" "$cross" "$UTIL_LINUX_VERSION" "$util_linux_src_dir" "$install_prefix"
    done
    rm -rf "$util_linux_src_dir"
    COMPONENT_BUILD_NOTE="built"
    return 0
  fi

  if [ "$override_used" = true ]; then
    echo "libblkid builds provided by environment overrides"
    COMPONENT_BUILD_NOTE="overridden"
  else
    echo "libblkid for arm and arm64 already current, skipping"
    COMPONENT_BUILD_NOTE="already current"
  fi
  return 2
}

build_libgcrypt_component() {
  set -e
  local arch
  local need_libgcrypt=false
  local override_used=false
  local libgpg_error_src_dir=""
  local libgcrypt_src_dir=""
  local cross=""
  local install_prefix=""

  for arch in arm arm64; do
    if component_override_used "libgcrypt" "$arch"; then
      override_used=true
      continue
    fi
    if ! component_is_current "libgcrypt" "$arch" "lib/pkgconfig/libgcrypt.pc" "$LIBGCRYPT_VERSION_MARKER"; then
      need_libgcrypt=true
      break
    fi
  done

  if [ "$need_libgcrypt" = true ]; then
    libgpg_error_src_dir=$(mktemp -d src/libgpg-error-XXXXXX)
    curl -L "$LIBGPG_ERROR_URL" | tar -xj -C "$libgpg_error_src_dir" --strip-components=1
    libgcrypt_src_dir=$(mktemp -d src/libgcrypt-XXXXXX)
    curl -L "$LIBGCRYPT_URL" | tar -xj -C "$libgcrypt_src_dir" --strip-components=1
    for arch in arm arm64; do
      case "$arch" in
        arm)
          cross="$CROSS_COMPILE_ARM"
          ;;
        arm64)
          cross="$CROSS_COMPILE_ARM64"
          ;;
        *)
          echo "Unsupported architecture '$arch' for libgcrypt build" >&2
          rm -rf "$libgpg_error_src_dir" "$libgcrypt_src_dir"
          COMPONENT_BUILD_NOTE="unsupported architecture"
          return 1
          ;;
      esac
      if component_override_used "libgcrypt" "$arch"; then
        echo "Skipping libgcrypt build for $arch; using prebuilt artifacts from $(component_prefix_path "libgcrypt" "$arch")"
        continue
      fi
      install_prefix="$(component_prefix_path "libgcrypt" "$arch")"
      if component_is_current "libgcrypt" "$arch" "lib/pkgconfig/libgcrypt.pc" "$LIBGCRYPT_VERSION_MARKER"; then
        echo "libgcrypt for $arch already current, skipping"
        continue
      fi
      "$SCRIPT_DIR/build_libgcrypt.sh" "$arch" "$cross" "$LIBGCRYPT_VERSION_MARKER" \
        "$libgpg_error_src_dir" "$libgcrypt_src_dir" "$install_prefix" "$LIBGPG_ERROR_VERSION"
    done
    rm -rf "$libgpg_error_src_dir" "$libgcrypt_src_dir"
    COMPONENT_BUILD_NOTE="built"
    return 0
  fi

  if [ "$override_used" = true ]; then
    echo "libgcrypt builds provided by environment overrides"
    COMPONENT_BUILD_NOTE="overridden"
  else
    echo "libgcrypt for arm and arm64 already current, skipping"
    COMPONENT_BUILD_NOTE="already current"
  fi
  return 2
}

build_libzstd_component() {
  set -e
  local arch
  local need_libzstd=false
  local override_used=false
  local zstd_src_dir=""
  local cross=""
  local install_prefix=""

  for arch in arm arm64; do
    if component_override_used "libzstd" "$arch"; then
      override_used=true
      continue
    fi
    if ! component_is_current "libzstd" "$arch" "lib/pkgconfig/libzstd.pc" "$LIBZSTD_VERSION"; then
      need_libzstd=true
      break
    fi
  done

  if [ "$need_libzstd" = true ]; then
    zstd_src_dir=$(mktemp -d src/libzstd-XXXXXX)
    curl -L "$LIBZSTD_URL" | tar -xz -C "$zstd_src_dir" --strip-components=1
    for arch in arm arm64; do
      if component_override_used "libzstd" "$arch"; then
        echo "Skipping libzstd build for $arch; using prebuilt artifacts from $(component_prefix_path "libzstd" "$arch")"
        continue
      fi

      if component_is_current "libzstd" "$arch" "lib/pkgconfig/libzstd.pc" "$LIBZSTD_VERSION"; then
        echo "libzstd for $arch already current, skipping"
        continue
      fi

      case "$arch" in
        arm)
          cross="$CROSS_COMPILE_ARM"
          ;;
        arm64)
          cross="$CROSS_COMPILE_ARM64"
          ;;
        *)
          echo "Unsupported architecture '$arch' for libzstd build" >&2
          rm -rf "$zstd_src_dir"
          COMPONENT_BUILD_NOTE="unsupported architecture"
          return 1
          ;;
      esac

      install_prefix="$(component_prefix_path "libzstd" "$arch")"
      "$SCRIPT_DIR/build_libzstd.sh" "$arch" "$cross" "$LIBZSTD_VERSION" "$zstd_src_dir" "$install_prefix"
    done
    rm -rf "$zstd_src_dir"
    COMPONENT_BUILD_NOTE="built"
    return 0
  fi

  if [ "$override_used" = true ]; then
    echo "libzstd builds provided by environment overrides"
    COMPONENT_BUILD_NOTE="overridden"
  else
    echo "libzstd for arm and arm64 already current, skipping"
    COMPONENT_BUILD_NOTE="already current"
  fi
  return 2
}

# Build systemd for ARM and ARM64

SYSTEMD_VERSION=255.4
SYSTEMD_URL="https://github.com/systemd/systemd-stable/archive/refs/tags/v${SYSTEMD_VERSION}.tar.gz"

build_systemd_component() {
  set -e
  local arch
  local need_systemd=false
  local systemd_src_dir=""
  local systemd_patch_dir=""
  local patch_file

  for arch in arm arm64; do
    if ! component_is_current "systemd" "$arch" "systemd" "$SYSTEMD_VERSION"; then
      need_systemd=true
      break
    fi
  done

  if [ "$need_systemd" = true ]; then
    systemd_src_dir=$(mktemp -d src/systemd-XXXXXX)
    curl -L "$SYSTEMD_URL" | tar -xz -C "$systemd_src_dir" --strip-components=1
    systemd_patch_dir="$SCRIPT_DIR/patches/systemd"
    if [ -d "$systemd_patch_dir" ]; then
      (
        cd "$systemd_src_dir"
        for patch_file in "$systemd_patch_dir"/*.patch; do
          [ -e "$patch_file" ] || continue
          patch -p1 -N < "$patch_file"
        done
      )
    fi
    "$SCRIPT_DIR/build_systemd.sh" arm "$CROSS_COMPILE_ARM" "$SYSTEMD_VERSION" "$systemd_src_dir"
    "$SCRIPT_DIR/build_systemd.sh" arm64 "$CROSS_COMPILE_ARM64" "$SYSTEMD_VERSION" "$systemd_src_dir"
    rm -rf "$systemd_src_dir"
    COMPONENT_BUILD_NOTE="built"
    return 0
  fi

  echo "systemd for arm and arm64 already current, skipping"
  COMPONENT_BUILD_NOTE="already current"
  return 2
}

build_lsb_root_component() {
  set -e

  local lsb_img
  local tmpfile
  local sys_root
  local systemd_bin
  local symlink_target
  local units_dir
  local component

  mkdir -p config/lsb_root

  lsb_img="$ARTIFACTS_DIR/images/lsb_root.img"
  rm -f "$lsb_img"
  mkdir -p "$(dirname "$lsb_img")"
  dd if=/dev/zero of="$lsb_img" bs=1M count=8
  mke2fs -F "$lsb_img" >/dev/null

  local d
  for d in /bin /etc /usr /usr/bin; do
    debugfs -w -R "mkdir $d" "$lsb_img" >/dev/null
  done

  tmpfile=$(mktemp)
  cat <<'EOF' > "$tmpfile"
DISTRIB_ID=L4Re
DISTRIB_RELEASE=1.0
DISTRIB_DESCRIPTION="L4Re root image"
EOF
  debugfs -w -R "write $tmpfile /etc/lsb-release" "$lsb_img" >/dev/null
  rm "$tmpfile"

  debugfs -w -R "write $ARTIFACTS_DIR/bash/arm64/bash /bin/sh" "$lsb_img" >/dev/null
  debugfs -w -R "set_inode_field /bin/sh mode 0100755" "$lsb_img" >/dev/null
  debugfs -w -R "write $ARTIFACTS_DIR/bash/arm64/bash /bin/bash" "$lsb_img" >/dev/null
  debugfs -w -R "set_inode_field /bin/bash mode 0100755" "$lsb_img" >/dev/null

  if should_build_component "systemd"; then
    sys_root="$ARTIFACTS_DIR/systemd/arm64/root"
    if [ -d "$sys_root" ]; then
      mkdir -p config/lsb_root/usr/lib/systemd
      mkdir -p config/lsb_root/lib/systemd
      if [ -d "$sys_root/usr/lib/systemd" ]; then
        cp -a "$sys_root/usr/lib/systemd/." config/lsb_root/usr/lib/systemd/
      fi
      systemd_bin="$sys_root/lib/systemd/systemd"
      if [ -f "$systemd_bin" ]; then
        cp "$systemd_bin" config/lsb_root/lib/systemd/systemd
        cp "$systemd_bin" config/lsb_root/usr/lib/systemd/systemd
        debugfs -w -R "mkdir /lib/systemd" "$lsb_img" >/dev/null
        debugfs -w -R "mkdir /usr/lib/systemd" "$lsb_img" >/dev/null
        debugfs -w -R "write $systemd_bin /lib/systemd/systemd" "$lsb_img" >/dev/null
        debugfs -w -R "set_inode_field /lib/systemd/systemd mode 0100755" "$lsb_img" >/dev/null
        debugfs -w -R "write $systemd_bin /usr/lib/systemd/systemd" "$lsb_img" >/dev/null
        debugfs -w -R "set_inode_field /usr/lib/systemd/systemd mode 0100755" "$lsb_img" >/dev/null
        if [ -d "$sys_root/usr/lib/systemd" ]; then
          find "$sys_root/usr/lib/systemd" -type d | while read -r subdir; do
            local rel
            rel="${subdir#$sys_root}"
            debugfs -w -R "mkdir $rel" "$lsb_img" >/dev/null || true
          done
          find "$sys_root/usr/lib/systemd" -type f | while read -r file; do
            local rel
            rel="${file#$sys_root}"
            debugfs -w -R "write $file $rel" "$lsb_img" >/dev/null
            debugfs -w -R "set_inode_field $rel mode 0100644" "$lsb_img" >/dev/null
          done
        fi
      fi
      if [ -f "$sys_root/usr/bin/systemctl" ]; then
        mkdir -p config/lsb_root/usr/bin
        cp "$sys_root/usr/bin/systemctl" config/lsb_root/usr/bin/systemctl
        chmod 0755 config/lsb_root/usr/bin/systemctl
        debugfs -w -R "write $sys_root/usr/bin/systemctl /usr/bin/systemctl" "$lsb_img" >/dev/null
        debugfs -w -R "set_inode_field /usr/bin/systemctl mode 0100755" "$lsb_img" >/dev/null
      fi
      if [ -L "$sys_root/bin/systemctl" ]; then
        mkdir -p config/lsb_root/bin
        symlink_target="$(readlink "$sys_root/bin/systemctl")"
        ln -snf "$symlink_target" config/lsb_root/bin/systemctl
        debugfs -w -R "symlink $symlink_target /bin/systemctl" "$lsb_img" >/dev/null || true
      fi
    fi
  fi

  stage_component_runtime_libraries() {
    local component="$1"
    local arch="$2"
    shift 2
    local -a patterns=("$@")
    if [ ${#patterns[@]} -eq 0 ]; then
      patterns=("$component.so*")
    fi

    local runtime_prefix
    runtime_prefix="$(component_prefix_path "$component" "$arch")"
    local -a stage_dirs=()
    local candidate
    for candidate in "$runtime_prefix/lib" "$runtime_prefix/lib64"; do
      if [ -d "$candidate" ]; then
        stage_dirs+=("$candidate")
      fi
    done

    if [ ${#stage_dirs[@]} -eq 0 ]; then
      return
    fi

    declare -A staged_files=()
    declare -A staged_links=()
    local pattern stage_dir
    for stage_dir in "${stage_dirs[@]}"; do
      for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' sofile; do
          staged_files["$sofile"]=1
        done < <(find "$stage_dir" -maxdepth 1 -type f -name "$pattern" -print0)
        while IFS= read -r -d '' solink; do
          staged_links["$solink"]=1
        done < <(find "$stage_dir" -maxdepth 1 -type l -name "$pattern" -print0)
      done
    done

    if [ ${#staged_files[@]} -eq 0 ] && [ ${#staged_links[@]} -eq 0 ]; then
      return
    fi

    echo "Staging $component shared libraries for $arch"
    mkdir -p config/lsb_root/lib config/lsb_root/usr/lib
    debugfs -w -R "mkdir /lib" "$lsb_img" >/dev/null || true
    debugfs -w -R "mkdir /usr/lib" "$lsb_img" >/dev/null || true

    local -a sorted_files=()
    mapfile -t sorted_files < <(printf '%s\n' "${!staged_files[@]}" | sort)
    local sofile base
    for sofile in "${sorted_files[@]}"; do
      [ -n "$sofile" ] || continue
      base="$(basename "$sofile")"
      cp "$sofile" "config/lsb_root/lib/$base"
      chmod 0644 "config/lsb_root/lib/$base"
      debugfs -w -R "rm /lib/$base" "$lsb_img" >/dev/null 2>&1 || true
      debugfs -w -R "write $sofile /lib/$base" "$lsb_img" >/dev/null
      debugfs -w -R "set_inode_field /lib/$base mode 0100644" "$lsb_img" >/dev/null
      ln -sf "../lib/$base" "config/lsb_root/usr/lib/$base"
      debugfs -w -R "rm /usr/lib/$base" "$lsb_img" >/dev/null 2>&1 || true
      debugfs -w -R "symlink ../lib/$base /usr/lib/$base" "$lsb_img" >/dev/null || true
    done

    local -a sorted_links=()
    mapfile -t sorted_links < <(printf '%s\n' "${!staged_links[@]}" | sort)
    local solink target
    for solink in "${sorted_links[@]}"; do
      [ -n "$solink" ] || continue
      base="$(basename "$solink")"
      target="$(readlink "$solink")"
      ln -sf "$target" "config/lsb_root/lib/$base"
      debugfs -w -R "rm /lib/$base" "$lsb_img" >/dev/null 2>&1 || true
      debugfs -w -R "symlink $target /lib/$base" "$lsb_img" >/dev/null || true
      ln -sf "../lib/$base" "config/lsb_root/usr/lib/$base"
      debugfs -w -R "rm /usr/lib/$base" "$lsb_img" >/dev/null 2>&1 || true
      debugfs -w -R "symlink ../lib/$base /usr/lib/$base" "$lsb_img" >/dev/null || true
    done
  }

  for component in "${SYSTEMD_COMPONENTS[@]}"; do
    if ! should_build_component "$component"; then
      continue
    fi
    case "$component" in
      libcap)
        stage_component_runtime_libraries "$component" "arm64" "libcap.so*" "libpsx.so*"
        ;;
      libgcrypt)
        stage_component_runtime_libraries "$component" "arm64" "libgcrypt.so*" "libgpg-error.so*"
        ;;
      *)
        stage_component_runtime_libraries "$component" "arm64" "$component.so*"
        ;;
    esac
  done

  if should_build_component "systemd"; then
    units_dir="config/systemd"
    if [ -d "$units_dir" ]; then
      mkdir -p config/lsb_root/lib/systemd/system
      debugfs -w -R "mkdir /lib/systemd/system" "$lsb_img" >/dev/null || true
      local unit base
      for unit in "$units_dir"/*.service; do
        [ -f "$unit" ] || continue
        base="$(basename "$unit")"
        cp "$unit" config/lsb_root/lib/systemd/system/
        debugfs -w -R "write $unit /lib/systemd/system/$base" "$lsb_img" >/dev/null
        debugfs -w -R "set_inode_field /lib/systemd/system/$base mode 0100644" "$lsb_img" >/dev/null
      done
    fi
  fi

  enable_service() {
    local name="$1"
    local unit="config/systemd/${name}.service"
    if [ -f "$unit" ]; then
      mkdir -p config/lsb_root/etc/systemd/system/multi-user.target.wants
      ln -sf ../../../../lib/systemd/system/${name}.service \
        config/lsb_root/etc/systemd/system/multi-user.target.wants/${name}.service
      debugfs -w -R "mkdir /etc/systemd" "$lsb_img" >/dev/null || true
      debugfs -w -R "mkdir /etc/systemd/system" "$lsb_img" >/dev/null || true
      debugfs -w -R "mkdir /etc/systemd/system/multi-user.target.wants" "$lsb_img" >/dev/null || true
      debugfs -w -R "symlink /lib/systemd/system/${name}.service /etc/systemd/system/multi-user.target.wants/${name}.service" "$lsb_img" >/dev/null
    fi
  }

  if should_build_component "systemd"; then
    enable_service bash
  fi

  COMPONENT_BUILD_NOTE="created"
  return 0
}

run_component_build "bash" build_bash_component
run_component_build "glibc" build_glibc_component
run_component_build "libcap" build_libcap_component
run_component_build "libcrypt" build_libcrypt_component
run_component_build "libblkid" build_libblkid_component
run_component_build "libgcrypt" build_libgcrypt_component
run_component_build "libzstd" build_libzstd_component
run_component_build "systemd" build_systemd_component

if (( BUILD_FAILURE_COUNT > 0 )); then
  echo "One or more external component builds failed; skipping remaining build steps."
  if [[ -z "${BUILD_RESULTS[lsb_root]+set}" ]]; then
    if should_build_component "lsb_root"; then
      BUILD_RESULTS["lsb_root"]="skipped"
      BUILD_NOTES["lsb_root"]="skipped (previous failures)"
    else
      BUILD_RESULTS["lsb_root"]="skipped"
      BUILD_NOTES["lsb_root"]="not selected"
    fi
  fi
else
  echo "######### EXTERNAL BUILD DONE ###############"

  # Build the tree including libc, Leo, and Rust crates
  gmake

  run_component_build "lsb_root" build_lsb_root_component

  resolve_realpath_portable() {
    local path="$1"

    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
      return 1
    fi

    local resolved
    if command -v realpath >/dev/null 2>&1; then
      if resolved=$(realpath "$path" 2>/dev/null); then
        printf '%s\n' "$resolved"
        return 0
      fi
    fi

    if command -v python3 >/dev/null 2>&1; then
      if resolved=$(python3 - "$path" <<'PY' 2>/dev/null); then
import os
import sys

try:
    print(os.path.realpath(sys.argv[1]))
except OSError:
    sys.exit(1)
PY
        printf '%s\n' "$resolved"
        return 0
      fi
    fi

    if command -v readlink >/dev/null 2>&1; then
      local current="$path"
      local dir
      local link

      if [[ "$current" != /* ]]; then
        dir=$(cd "$(dirname "$current")" && pwd -P) || return 1
        current="$dir/$(basename "$current")"
      fi

      while [ -L "$current" ]; do
        link=$(readlink "$current") || return 1
        if [[ "$link" == /* ]]; then
          current="$link"
        else
          current="$(dirname "$current")/$link"
        fi
        if [[ "$current" != /* ]]; then
          dir=$(cd "$(dirname "$current")" && pwd -P) || return 1
          current="$dir/$(basename "$current")"
        fi
      done

      printf '%s\n' "$current"
      return 0
    fi

    return 1
  }

  # Collect key build artifacts
  stage_bootable_images() {
    local source_root="obj/l4"
    local distribution_dir="distribution"
    local distribution_images_dir="$distribution_dir/images"

    mkdir -p "$distribution_images_dir"

    if [ ! -d "$source_root" ]; then
      return
    fi

    local -a images=()
    while IFS= read -r -d '' image; do
      images+=("$image")
    done < <(find "$source_root" \
      -path '*/images/*' \
      \( -name '*.elf' -o -name '*.uimage' \) \
      \( -type f -o -type l \) \
      -print0 2>/dev/null)

    if (( ${#images[@]} == 0 )); then
      return
    fi

    local image mtime
    local -a sorted_entries=()
    mapfile -t sorted_entries < <(
      for image in "${images[@]}"; do
        if ! mtime=$(stat -c %Y "$image" 2>/dev/null); then
          if ! mtime=$(stat -f %m "$image" 2>/dev/null); then
            mtime=0
          fi
        fi
        printf '%011d\t%s\n' "$mtime" "$image"
      done | sort -n -k1,1 -k2
    )

    local entry file source_path resolved base dest_path
    for entry in "${sorted_entries[@]}"; do
      file="${entry#*$'\t'}"
      [ -n "$file" ] || continue
      source_path="$file"
      if [ -L "$file" ]; then
        if resolved=$(resolve_realpath_portable "$file" 2>/dev/null); then
          source_path="$resolved"
        else
          echo "Warning: unable to resolve symlink $file; skipping"
          continue
        fi
      fi

      base="$(basename "$source_path")"
      dest_path="$distribution_images_dir/$base"

      if [ "$source_path" != "$file" ]; then
        echo "Staging image $base from $source_path (via $file) into $distribution_images_dir"
      else
        echo "Staging image $base from $source_path into $distribution_images_dir"
      fi
      cp -f "$source_path" "$dest_path"
    done
  }

  stage_bootable_images
fi
