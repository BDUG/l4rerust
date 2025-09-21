#!/usr/bin/env bash
# shellcheck shell=bash

if [[ -n "${COMPONENT_ARTIFACTS_SH_SOURCED:-}" ]]; then
  return 0
fi
COMPONENT_ARTIFACTS_SH_SOURCED=1

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common_build.sh
source "$LIB_DIR/../common_build.sh"

readonly -a STAGED_COMPONENTS=(
  glibc
  libcap
  libcrypt
  libblkid
  libgcrypt
  libzstd
)

# Convert a component or architecture name into the suffix used by the
# environment variables that override staging prefixes.
to_env_suffix() {
  local value="$1"
  value="${value//-/_}"
  printf '%s' "${value^^}"
}

# Return the override environment variable name for the given component and
# architecture if one is set.
component_override_env_var_name() {
  local component="$1" arch="$2"
  local component_suffix
  component_suffix=$(to_env_suffix "$component")
  local arch_suffix
  arch_suffix=$(to_env_suffix "$arch")

  local base_var="SYSTEMD_${component_suffix}_PREFIX"
  local arch_var="${base_var}_${arch_suffix}"

  if [ -n "${!arch_var-}" ]; then
    printf '%s' "$arch_var"
    return 0
  fi

  if [ -n "${!base_var-}" ]; then
    printf '%s' "$base_var"
    return 0
  fi

  return 1
}

resolve_and_validate_component_override_prefix() {
  local component="$1" arch="$2" prefix="$3" env_var="$4"

  if [ ! -d "$prefix" ]; then
    echo "Environment variable $env_var (for $component $arch) points to '$prefix', which does not exist" >&2
    exit 1
  fi

  prefix="$(resolve_path "$prefix")"

  local missing=()
  local subdir
  for subdir in include lib lib/pkgconfig; do
    if [ ! -d "$prefix/$subdir" ]; then
      missing+=("$prefix/$subdir")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo "Environment variable $env_var (for $component $arch) points to '$prefix', but the following required directories are missing:" >&2
    local path
    for path in "${missing[@]}"; do
      echo "  - $path" >&2
    done
    exit 1
  fi

  printf '%s' "$prefix"
}

declare -A SYSTEMD_COMPONENT_PREFIXES=()
declare -A SYSTEMD_COMPONENT_OVERRIDE_USED=()

component_prefix_path() {
  local component="$1" arch="$2"
  printf '%s' "${SYSTEMD_COMPONENT_PREFIXES["$component:$arch"]}"
}

component_override_used() {
  local component="$1" arch="$2"
  [[ "${SYSTEMD_COMPONENT_OVERRIDE_USED["$component:$arch"]:-0}" == 1 ]]
}

initialize_component_prefixes() {
  if [ -z "${REPO_ROOT:-}" ]; then
    echo "REPO_ROOT must be set before calling initialize_component_prefixes" >&2
    exit 1
  fi
  if [ -z "${ARTIFACTS_DIR:-}" ]; then
    echo "ARTIFACTS_DIR must be set before calling initialize_component_prefixes" >&2
    exit 1
  fi
  local component arch key env_var prefix
  for component in "${STAGED_COMPONENTS[@]}"; do
    for arch in arm arm64; do
      key="$component:$arch"
      if env_var=$(component_override_env_var_name "$component" "$arch"); then
        prefix="${!env_var}"
        if [ -z "$prefix" ]; then
          echo "Environment variable $env_var is set but empty" >&2
          exit 1
        fi
        prefix="$(resolve_and_validate_component_override_prefix "$component" "$arch" "$prefix" "$env_var")"
        SYSTEMD_COMPONENT_PREFIXES["$key"]="$prefix"
        SYSTEMD_COMPONENT_OVERRIDE_USED["$key"]=1
        echo "Using prebuilt $component for $arch from $prefix ($env_var)"
      else
        prefix="$REPO_ROOT/$ARTIFACTS_DIR/$component/$arch"
        SYSTEMD_COMPONENT_PREFIXES["$key"]="$prefix"
        SYSTEMD_COMPONENT_OVERRIDE_USED["$key"]=0
      fi
    done
  done
}

# Check whether a component artifact is present and matches the expected
# version recorded in the VERSION marker file.
component_is_current() {
  local component="$1" arch="$2" artifact="$3" expected_version="$4"
  local component_dir="$ARTIFACTS_DIR/$component/$arch"
  local artifact_path="$component_dir/$artifact"
  local version_file="$component_dir/VERSION"

  if [ ! -f "$artifact_path" ]; then
    return 1
  fi

  if [ ! -f "$version_file" ]; then
    return 1
  fi

  local recorded_version
  recorded_version=$(<"$version_file") || return 1
  if [ "$recorded_version" != "$expected_version" ]; then
    return 1
  fi

  return 0
}
