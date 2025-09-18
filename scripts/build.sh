#!/usr/bin/env bash
set -euo pipefail

echo "Entering build container"
trap 'echo "Leaving build container"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"
cd "$REPO_ROOT"

# Usage: build.sh [--clean|--no-clean]
#   --clean     Remove previous build directories before building (default)
#   --no-clean  Skip removal of build directories
clean=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      clean=true
      shift
      ;;
    --no-clean)
      clean=false
      shift
      ;;
    *)
      echo "Usage: $0 [--clean|--no-clean]" >&2
      exit 1
      ;;
  esac
done

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

readonly -a SYSTEMD_COMPONENTS=(
  libcap
  libcrypt
  libblkid
  libgcrypt
  libmount
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
  local component arch key env_var prefix
  for component in "${SYSTEMD_COMPONENTS[@]}"; do
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

# Start from a clean state if requested
if [ "$clean" = true ]; then
  "$SCRIPT_DIR/setup.sh" clean
fi

mkdir -p "$ARTIFACTS_DIR"

initialize_component_prefixes

# Configure for ARM using setup script
export CROSS_COMPILE_ARM CROSS_COMPILE_ARM64
# Run the setup tool. If a pre-generated configuration is available, reuse it
# to avoid the interactive `config` step.
if [ -f /workspace/.config ]; then
  echo "Using configuration from /workspace/.config"
  mkdir -p obj
  cp /workspace/.config obj/.config
elif [ -f "$SCRIPT_DIR/l4re.config" ]; then
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

# Build a statically linked Bash for ARM and ARM64
build_bash() {
  local arch="$1" cross="$2" expected_version="$3"
  local triple="$(${cross}g++ -dumpmachine)"
  if [[ "$triple" != *-linux-* && "$triple" != *-elf* ]]; then
    echo "${cross}g++ targets '$triple', which is neither a Linux nor ELF target" >&2
    exit 1
  fi
  local host="$triple"
  local cpu="${triple%%-*}"
  local out_dir="$ARTIFACTS_DIR/bash/$arch"
  if component_is_current "bash" "$arch" "bash" "$expected_version"; then
    echo "bash for $arch already current, skipping"
    return
  fi
  mkdir -p "$out_dir"
  (
    cd "$bash_src_dir"
    gmake distclean >/dev/null 2>&1 || true
    CC="${cross}gcc" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" \
      ./configure --host="$host" --without-bash-malloc
    gmake clean
    CC="${cross}gcc" CXX="${cross}g++" AR="${cross}ar" RANLIB="${cross}ranlib" \
      gmake STATIC_LDFLAGS=-static
    cp bash "$REPO_ROOT/$out_dir/"
  )
  echo "$expected_version" > "$out_dir/VERSION"
}

BASH_VERSION=5.2.21
BASH_URL="https://ftp.gnu.org/gnu/bash/bash-${BASH_VERSION}.tar.gz"

build_libcap() {
  local arch="$1" cross="$2" expected_version="$3"
  local triple="$(${cross}g++ -dumpmachine)"
  local microkernel=false
  if [[ "$triple" == *-linux-* ]]; then
    microkernel=false
  elif [[ "$triple" == *-elf-* || "$triple" == *-elf ]]; then
    microkernel=true
  else
    echo "${cross}g++ targets '$triple', but libcap requires a Linux or L4Re ELF toolchain" >&2
    exit 1
  fi
  if component_override_used "libcap" "$arch"; then
    echo "Skipping libcap build for $arch; using prebuilt artifacts from $(component_prefix_path "libcap" "$arch")"
    return
  fi
  local install_prefix
  install_prefix="$(component_prefix_path "libcap" "$arch")"
  if component_is_current "libcap" "$arch" "lib/pkgconfig/libcap.pc" "$expected_version"; then
    echo "libcap for $arch already current, skipping"
    return
  fi
  rm -rf "$install_prefix"
  mkdir -p "$install_prefix"
  local -a make_args=(
    "BUILD_CC=gcc"
    "CC=${cross}gcc"
    "AR=${cross}ar"
    "RANLIB=${cross}ranlib"
    "prefix=$install_prefix"
    "lib=lib"
  )
  if [ "$microkernel" = true ]; then
    make_args+=(
      "KERNEL_HEADERS=$REPO_ROOT/pkg/include"
      "PTHREADS=no"
      "SHARED=no"
    )
  fi
  (
    cd "$libcap_src_dir"
    gmake -C libcap "${make_args[@]}" distclean >/dev/null 2>&1 || true
    gmake -C libcap "${make_args[@]}" clean >/dev/null 2>&1 || true
    gmake -C libcap "${make_args[@]}" install
  )
  if [ "$microkernel" = true ]; then
    local shim_header="$REPO_ROOT/pkg/include/linux/capability.h"
    if [ ! -f "$shim_header" ]; then
      echo "Missing capability shim header at $shim_header" >&2
      exit 1
    fi
    mkdir -p "$install_prefix/include/linux"
    cp "$shim_header" "$install_prefix/include/linux/"
  fi
  local pkgconfig_file="$install_prefix/lib/pkgconfig/libcap.pc"
  if [ -f "$pkgconfig_file" ]; then
    local tmp_pc
    tmp_pc=$(mktemp)
    sed "s/^Version:.*/Version: $expected_version/" "$pkgconfig_file" >"$tmp_pc"
    mv "$tmp_pc" "$pkgconfig_file"
  else
    mkdir -p "$install_prefix/lib/pkgconfig"
    cat >"$pkgconfig_file" <<EOF
prefix=$install_prefix
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libcap
Description: POSIX capabilities library
Version: $expected_version
Libs: -L\${libdir} -lcap
Cflags: -I\${includedir}
EOF
  fi
  echo "$expected_version" > "$install_prefix/VERSION"
}

LIBCAP_VERSION=2.69
LIBCAP_URL="https://git.kernel.org/pub/scm/libs/libcap/libcap.git/snapshot/libcap-${LIBCAP_VERSION}.tar.gz"

build_libcrypt() {
  local arch="$1" cross="$2" expected_version="$3"
  local triple="$(${cross}g++ -dumpmachine)"
  if [[ "$triple" != *-linux-* && "$triple" != *-elf* ]]; then
    echo "${cross}g++ targets '$triple', which is neither a Linux nor ELF target" >&2
    exit 1
  fi

  if component_override_used "libcrypt" "$arch"; then
    echo "Skipping libcrypt build for $arch; using prebuilt artifacts from $(component_prefix_path "libcrypt" "$arch")"
    return
  fi

  local install_prefix
  install_prefix="$(component_prefix_path "libcrypt" "$arch")"
  if component_is_current "libcrypt" "$arch" "lib/pkgconfig/libcrypt.pc" "$expected_version"; then
    echo "libcrypt for $arch already current, skipping"
    return
  fi
  rm -rf "$install_prefix"
  mkdir -p "$install_prefix"

  local -a configure_args=(
    "--host=$triple"
    "--prefix=$install_prefix"
  )

  local microkernel=false
  if [[ "$triple" == *-elf-* || "$triple" == *-elf ]]; then
    microkernel=true
    configure_args+=("--disable-shared")
  fi

  (
    cd "$libxcrypt_src_dir"
    gmake distclean >/dev/null 2>&1 || true
    gmake clean >/dev/null 2>&1 || true

    export CC="${cross}gcc"
    export AR="${cross}ar"
    export RANLIB="${cross}ranlib"
    export STRIP="${cross}strip"
    if [ "$microkernel" = true ]; then
      export ac_cv_lib_pthread_pthread_create=no
      export ac_cv_header_pthread_h=no
    else
      unset ac_cv_lib_pthread_pthread_create
      unset ac_cv_header_pthread_h
    fi

    ./configure "${configure_args[@]}"
    gmake
    gmake install
  )

  local pkgconfig_dir="$install_prefix/lib/pkgconfig"
  if [ -d "$pkgconfig_dir" ] && [ ! -f "$pkgconfig_dir/libcrypt.pc" ] && [ -f "$pkgconfig_dir/libxcrypt.pc" ]; then
    ln -sf libxcrypt.pc "$pkgconfig_dir/libcrypt.pc"
  fi

  echo "$expected_version" > "$install_prefix/VERSION"
}

LIBXCRYPT_VERSION=4.4.36
LIBXCRYPT_URL="https://github.com/besser82/libxcrypt/releases/download/v${LIBXCRYPT_VERSION}/libxcrypt-${LIBXCRYPT_VERSION}.tar.xz"

need_bash=false
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
  build_bash arm "$CROSS_COMPILE_ARM" "$BASH_VERSION"
  build_bash arm64 "$CROSS_COMPILE_ARM64" "$BASH_VERSION"
  rm -rf "$bash_src_dir"
else
  echo "bash for arm and arm64 already current, skipping"
fi

need_libcap=false
for arch in arm arm64; do
  if component_override_used "libcap" "$arch"; then
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
  build_libcap arm "$CROSS_COMPILE_ARM" "$LIBCAP_VERSION"
  build_libcap arm64 "$CROSS_COMPILE_ARM64" "$LIBCAP_VERSION"
  rm -rf "$libcap_src_dir"
else
  if component_override_used "libcap" arm || component_override_used "libcap" arm64; then
    echo "libcap builds provided by environment overrides"
  else
    echo "libcap for arm and arm64 already current, skipping"
  fi
fi

# Build libcrypt (libxcrypt) for ARM and ARM64
need_libcrypt=false
for arch in arm arm64; do
  if component_override_used "libcrypt" "$arch"; then
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
  build_libcrypt arm "$CROSS_COMPILE_ARM" "$LIBXCRYPT_VERSION"
  build_libcrypt arm64 "$CROSS_COMPILE_ARM64" "$LIBXCRYPT_VERSION"
  rm -rf "$libxcrypt_src_dir"
else
  if component_override_used "libcrypt" arm || component_override_used "libcrypt" arm64; then
    echo "libcrypt builds provided by environment overrides"
  else
    echo "libcrypt for arm and arm64 already current, skipping"
  fi
fi

# Build systemd for ARM and ARM64
build_systemd() {
  local arch="$1" cross="$2" expected_version="$3"
  local triple="$(${cross}g++ -dumpmachine)"
  if [[ "$triple" != *-linux-* ]]; then
    echo "${cross}g++ targets '$triple', but systemd requires a Linux-targeted toolchain" >&2
    echo "Please use a cross compiler whose triple contains '-linux-' to build systemd." >&2
    exit 1
  fi
  local host="$triple"
  local cpu="${triple%%-*}"
  local out_dir="$ARTIFACTS_DIR/systemd/$arch"
  local -a systemd_stage_prefixes=()
  local component
  for component in "${SYSTEMD_COMPONENTS[@]}"; do
    systemd_stage_prefixes+=("$(component_prefix_path "$component" "$arch")")
  done
  if component_is_current "systemd" "$arch" "systemd" "$expected_version"; then
    echo "systemd for $arch already current, skipping"
    return
  fi
  mkdir -p "$out_dir"
  (
    cd "$systemd_src_dir"
    # Meson relies on pkg-config for dependency discovery. Ensure the staged
    # libcap pkg-config metadata is visible without hiding the rest of the
    # cross sysroot. Capture the original pkg-config search variables so we can
    # extend them for the duration of this subshell.
    local old_pkg_config_path="${PKG_CONFIG_PATH:-}"
    local old_pkg_config_libdir="${PKG_CONFIG_LIBDIR:-}"
    local old_pkg_config_sysroot="${PKG_CONFIG_SYSROOT_DIR:-}"

    local sysroot
    sysroot="$(${cross}gcc --print-sysroot 2>/dev/null || true)"
    local multiarch
    multiarch="$(${cross}gcc -print-multiarch 2>/dev/null || true)"

    local new_pkg_config_path="$old_pkg_config_path"
    local -a staged_pkgconfig_dirs=()
    local idx
    for idx in "${!SYSTEMD_COMPONENTS[@]}"; do
      local prefix="${systemd_stage_prefixes[$idx]}"
      local pc_dir
      for pc_dir in "$prefix/lib/pkgconfig" "$prefix/lib64/pkgconfig"; do
        if [ -d "$pc_dir" ]; then
          staged_pkgconfig_dirs+=("$pc_dir")
        fi
      done
    done

    if [ ${#staged_pkgconfig_dirs[@]} -gt 0 ]; then
      local staged_dir
      local idx
      for (( idx=${#staged_pkgconfig_dirs[@]}-1; idx>=0; idx-- )); do
        staged_dir="${staged_pkgconfig_dirs[$idx]}"
        if [ -n "$new_pkg_config_path" ]; then
          new_pkg_config_path="$staged_dir:$new_pkg_config_path"
        else
          new_pkg_config_path="$staged_dir"
        fi
      done
    fi

    local -a pkgconfig_dirs=("${staged_pkgconfig_dirs[@]}")

    if [ -n "$sysroot" ]; then
      local -a sysroot_pkgconfig_dirs=(
        "$sysroot/usr/lib/pkgconfig"
        "$sysroot/usr/share/pkgconfig"
        "$sysroot/lib/pkgconfig"
      )
      if [ -n "$multiarch" ]; then
        sysroot_pkgconfig_dirs+=(
          "$sysroot/usr/lib/$multiarch/pkgconfig"
          "$sysroot/lib/$multiarch/pkgconfig"
        )
      fi
      local dir
      for dir in "${sysroot_pkgconfig_dirs[@]}"; do
        if [ -d "$dir" ]; then
          pkgconfig_dirs+=("$dir")
        fi
      done
    fi

    if [ -n "$old_pkg_config_libdir" ]; then
      local IFS=':'
      local old_pkgconfig_dirs=()
      read -r -a old_pkgconfig_dirs <<<"$old_pkg_config_libdir"
      pkgconfig_dirs+=("${old_pkgconfig_dirs[@]}")
    fi

    local new_pkg_config_libdir=""
    if [ ${#pkgconfig_dirs[@]} -gt 0 ]; then
      local IFS=':'
      new_pkg_config_libdir="${pkgconfig_dirs[*]}"
    fi

    if [ -n "$new_pkg_config_path" ]; then
      export PKG_CONFIG_PATH="$new_pkg_config_path"
    else
      unset PKG_CONFIG_PATH
    fi

    if [ -n "$new_pkg_config_libdir" ]; then
      export PKG_CONFIG_LIBDIR="$new_pkg_config_libdir"
    elif [ -n "$old_pkg_config_libdir" ]; then
      export PKG_CONFIG_LIBDIR="$old_pkg_config_libdir"
    else
      unset PKG_CONFIG_LIBDIR
    fi

    local overlay_sysroot=""
    if [ -n "$sysroot" ]; then
      overlay_sysroot="$REPO_ROOT/$ARTIFACTS_DIR/pkgconfig-sysroots/$arch"
      rm -rf "$overlay_sysroot"
      mkdir -p "$overlay_sysroot"
      if [ -d "$sysroot" ]; then
        while IFS= read -r -d '' entry; do
          local base
          base="$(basename "$entry")"
          ln -sfn "$entry" "$overlay_sysroot/$base"
        done < <(find "$sysroot" -mindepth 1 -maxdepth 1 -print0)
      fi
    fi

    if [ -z "$overlay_sysroot" ]; then
      overlay_sysroot="$REPO_ROOT/$ARTIFACTS_DIR/pkgconfig-sysroots/$arch"
      rm -rf "$overlay_sysroot"
      mkdir -p "$overlay_sysroot"
    fi

    local stage_prefix
    for stage_prefix in "${systemd_stage_prefixes[@]}"; do
      if [ -d "$stage_prefix" ]; then
        local rel_path="${stage_prefix#/}"
        local rel_dir
        rel_dir="$(dirname "$rel_path")"
        mkdir -p "$overlay_sysroot/$rel_dir"
        ln -sfn "$stage_prefix" "$overlay_sysroot/$rel_path"
      fi
    done

    if [ -n "$overlay_sysroot" ]; then
      export PKG_CONFIG_SYSROOT_DIR="$overlay_sysroot"
    elif [ -n "$old_pkg_config_sysroot" ]; then
      export PKG_CONFIG_SYSROOT_DIR="$old_pkg_config_sysroot"
    else
      unset PKG_CONFIG_SYSROOT_DIR
    fi

    local -a staged_lib_dirs=()
    local lib_dir
    for idx in "${!SYSTEMD_COMPONENTS[@]}"; do
      local prefix="${systemd_stage_prefixes[$idx]}"
      for lib_dir in "$prefix/lib" "$prefix/lib64"; do
        if [ -d "$lib_dir" ]; then
          staged_lib_dirs+=("$lib_dir")
        fi
      done
    done

    if [ ${#staged_lib_dirs[@]} -gt 0 ]; then
      local staged_lib_path=""
      for lib_dir in "${staged_lib_dirs[@]}"; do
        if [ -n "$staged_lib_path" ]; then
          staged_lib_path="$staged_lib_path:$lib_dir"
        else
          staged_lib_path="$lib_dir"
        fi
      done

      local old_library_path="${LIBRARY_PATH:-}"
      if [ -n "$old_library_path" ]; then
        export LIBRARY_PATH="$staged_lib_path:$old_library_path"
      else
        export LIBRARY_PATH="$staged_lib_path"
      fi

      local old_ld_library_path="${LD_LIBRARY_PATH:-}"
      if [ -n "$old_ld_library_path" ]; then
        export LD_LIBRARY_PATH="$staged_lib_path:$old_ld_library_path"
      else
        export LD_LIBRARY_PATH="$staged_lib_path"
      fi
    fi
    builddir="build-$arch"
    rm -rf "$builddir"
    mkdir -p "$builddir"
    cat > cross.txt <<EOF
[binaries]
c = '${cross}gcc'
cpp = '${cross}g++'
ar = '${cross}ar'
strip = '${cross}strip'

[host_machine]
system = 'linux'
cpu_family = '${cpu}'
cpu = '${cpu}'
endian = 'little'
EOF
    local -a meson_setup_args=(
      "$builddir"
      --cross-file cross.txt
      --prefix=/usr
      -Dhomed=disabled
      -Dfirstboot=false
      -Dtests=false
      -Dmachined=false
      -Dnetworkd=false
      -Dcheck-filesystems=false
      -Dnss-myhostname=false
      -Dnss-mymachines=disabled
      -Dnss-resolve=disabled
      -Dnss-systemd=false
      -Dportabled=false
      -Dresolve=false
      -Dtimesyncd=false
      -Dbacklight=false
      -Dbinfmt=false
      -Dcoredump=false
      -Dhibernate=false
      -Dhostnamed=false
      -Dhwdb=false
      -Dlocaled=false
      -Dlogind=false
      -Djournald=false
      -Dpstore=false
      -Dquotacheck=false
      -Drandomseed=false
      -Drfkill=false
      -Dsysext=false
      -Dtimedated=false
      -Dtmpfiles=false
      -Duserdb=false
      -Dvconsole=false
      -Dudev=false
      -Dremovable=false
      -Daudit=disabled
      -Dbzip2=disabled
      -Delfutils=disabled
      -Dgnutls=disabled
      -Didn=false
      -Dlibiptc=disabled
      -Dlz4=disabled
      -Dopenssl=disabled
      -Dpcre2=disabled
      -Dpolkit=disabled
      -Dpwquality=disabled
      -Dseccomp=disabled
      -Dselinux=disabled
      -Dtpm=false
      -Dtpm2=disabled
      -Dxz=disabled
      -Dzlib=disabled
    )
    meson setup "${meson_setup_args[@]}"
    ninja -C "$builddir" systemd || ninja -C "$builddir"
    DESTDIR="$REPO_ROOT/$out_dir/root" meson install -C "$builddir"
    cp "$REPO_ROOT/$out_dir/root/lib/systemd/systemd" "$REPO_ROOT/$out_dir/"
  )
  echo "$expected_version" > "$out_dir/VERSION"
}

SYSTEMD_VERSION=255.4
SYSTEMD_URL="https://github.com/systemd/systemd-stable/archive/refs/tags/v${SYSTEMD_VERSION}.tar.gz"

need_systemd=false
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
  build_systemd arm "$CROSS_COMPILE_ARM" "$SYSTEMD_VERSION"
  build_systemd arm64 "$CROSS_COMPILE_ARM64" "$SYSTEMD_VERSION"
  rm -rf "$systemd_src_dir"
else
  echo "systemd for arm and arm64 already current, skipping"
fi

# Build the tree including libc, Leo, and Rust crates
gmake

# Create a minimal LSB root filesystem image
lsb_img="$ARTIFACTS_DIR/images/lsb_root.img"
rm -f "$lsb_img"
mkdir -p "$(dirname "$lsb_img")"
dd if=/dev/zero of="$lsb_img" bs=1M count=8
mke2fs -F "$lsb_img" >/dev/null
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
debugfs -w -R "chmod 0755 /bin/sh" "$lsb_img" >/dev/null
debugfs -w -R "write $ARTIFACTS_DIR/bash/arm64/bash /bin/bash" "$lsb_img" >/dev/null
debugfs -w -R "chmod 0755 /bin/bash" "$lsb_img" >/dev/null

# Install systemd into the root filesystem image and staging area
sys_root="$ARTIFACTS_DIR/systemd/arm64/root"
if [ -d "$sys_root" ]; then
  mkdir -p config/lsb_root/usr/lib/systemd
  mkdir -p config/lsb_root/lib/systemd
  if [ -d "$sys_root/usr/lib/systemd" ]; then
    cp -r "$sys_root/usr/lib/systemd/"* config/lsb_root/usr/lib/systemd/ 2>/dev/null || true
  fi
  if [ -f "$sys_root/lib/systemd/systemd" ]; then
    cp "$sys_root/lib/systemd/systemd" config/lsb_root/lib/systemd/systemd
    cp "$sys_root/lib/systemd/systemd" config/lsb_root/usr/lib/systemd/systemd
    debugfs -w -R "mkdir /lib/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "mkdir /usr/lib/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "write $sys_root/lib/systemd/systemd /lib/systemd/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "chmod 0755 /lib/systemd/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "write $sys_root/lib/systemd/systemd /usr/lib/systemd/systemd" "$lsb_img" >/dev/null
    debugfs -w -R "chmod 0755 /usr/lib/systemd/systemd" "$lsb_img" >/dev/null
    if [ -d "$sys_root/usr/lib/systemd" ]; then
      find "$sys_root/usr/lib/systemd" -type d | while read -r d; do
        rel="${d#$sys_root}"
        debugfs -w -R "mkdir $rel" "$lsb_img" >/dev/null || true
      done
      find "$sys_root/usr/lib/systemd" -type f | while read -r f; do
        rel="${f#$sys_root}"
        debugfs -w -R "write $f $rel" "$lsb_img" >/dev/null
        debugfs -w -R "chmod 0644 $rel" "$lsb_img" >/dev/null
      done
    fi
  fi
fi

# Stage runtime libraries from staged components in the root filesystem image
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
    debugfs -w -R "chmod 0644 /lib/$base" "$lsb_img" >/dev/null
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
  case "$component" in
    libcap)
      stage_component_runtime_libraries "$component" "arm64" "libcap.so*" "libpsx.so*"
      ;;
    *)
      stage_component_runtime_libraries "$component" "arm64" "$component.so*"
      ;;
  esac
done

# Install systemd unit files into the image
units_dir="config/systemd"
if [ -d "$units_dir" ]; then
  mkdir -p config/lsb_root/lib/systemd/system
  debugfs -w -R "mkdir /lib/systemd/system" "$lsb_img" >/dev/null || true
  for unit in "$units_dir"/*.service; do
    [ -f "$unit" ] || continue
    base="$(basename "$unit")"
    cp "$unit" config/lsb_root/lib/systemd/system/
    debugfs -w -R "write $unit /lib/systemd/system/$base" "$lsb_img" >/dev/null
    debugfs -w -R "chmod 0644 /lib/systemd/system/$base" "$lsb_img" >/dev/null
  done
fi

# Enable services
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

enable_service bash

# Collect key build artifacts
mkdir -p "$ARTIFACTS_DIR/images"
if [ -f "obj/l4/arm64/images/bootstrap_hello_arm_virt.elf" ]; then
  cp "obj/l4/arm64/images/bootstrap_hello_arm_virt.elf" "$ARTIFACTS_DIR/images/" 2>/dev/null || true
fi
