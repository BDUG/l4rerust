#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"
# shellcheck source=lib/component_artifacts.sh
source "$SCRIPT_DIR/lib/component_artifacts.sh"

if [ $# -ne 4 ]; then
  echo "Usage: $0 <arch> <cross_prefix> <expected_version> <systemd_src_dir>" >&2
  exit 1
fi

arch="$1"
cross="$2"
expected_version="$3"
systemd_src_dir="$4"

if [ -z "$arch" ]; then
  echo "Architecture argument is required" >&2
  exit 1
fi

if [ -z "$cross" ]; then
  echo "Cross-compiler prefix argument is required" >&2
  exit 1
fi

if [ -z "$expected_version" ]; then
  echo "Expected version argument is required" >&2
  exit 1
fi

if [ ! -d "$systemd_src_dir" ]; then
  echo "Systemd source directory '$systemd_src_dir' does not exist" >&2
  exit 1
fi

systemd_src_dir="$(resolve_path "$systemd_src_dir")"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-out}"

cd "$REPO_ROOT"

initialize_component_prefixes

pkg_config_bin=""
if command -v pkg-config >/dev/null 2>&1; then
  pkg_config_bin="$(command -v pkg-config)"
elif command -v pkgconf >/dev/null 2>&1; then
  pkg_config_bin="$(command -v pkgconf)"
else
  echo "pkg-config not found; please install pkg-config or pkgconf" >&2
  exit 1
fi

triple="$(${cross}g++ -dumpmachine)"
if [[ "$triple" != *-linux-* ]]; then
  echo "${cross}g++ targets '$triple', but systemd requires a Linux-targeted toolchain" >&2
  echo "Please use a cross compiler whose triple contains '-linux-' to build systemd." >&2
  exit 1
fi

cpu="${triple%%-*}"
out_dir_rel="$ARTIFACTS_DIR/systemd/$arch"
out_dir="$REPO_ROOT/$out_dir_rel"

systemd_stage_prefixes=()
for component in "${SYSTEMD_COMPONENTS[@]}"; do
  systemd_stage_prefixes+=("$(component_prefix_path "$component" "$arch")")
done

if component_is_current "systemd" "$arch" "systemd" "$expected_version"; then
  echo "systemd for $arch already current, skipping"
  exit 0
fi

mkdir -p "$out_dir"
(
  cd "$systemd_src_dir"

  old_pkg_config_path="${PKG_CONFIG_PATH:-}"
  old_pkg_config_libdir="${PKG_CONFIG_LIBDIR:-}"
  old_pkg_config_sysroot="${PKG_CONFIG_SYSROOT_DIR:-}"

  sysroot="$(${cross}gcc --print-sysroot 2>/dev/null || true)"
  multiarch="$(${cross}gcc -print-multiarch 2>/dev/null || true)"

  new_pkg_config_path="$old_pkg_config_path"
  staged_pkgconfig_dirs=()
  for idx in "${!SYSTEMD_COMPONENTS[@]}"; do
    prefix="${systemd_stage_prefixes[$idx]}"
    for pc_dir in "$prefix/lib/pkgconfig" "$prefix/lib64/pkgconfig"; do
      if [ -d "$pc_dir" ]; then
        staged_pkgconfig_dirs+=("$pc_dir")
      fi
    done
  done

  if [ ${#staged_pkgconfig_dirs[@]} -gt 0 ]; then
    for (( idx=${#staged_pkgconfig_dirs[@]}-1; idx>=0; idx-- )); do
      staged_dir="${staged_pkgconfig_dirs[$idx]}"
      if [ -n "$new_pkg_config_path" ]; then
        new_pkg_config_path="$staged_dir:$new_pkg_config_path"
      else
        new_pkg_config_path="$staged_dir"
      fi
    done
  fi

  pkgconfig_dirs=("${staged_pkgconfig_dirs[@]}")

  if [ -n "$sysroot" ]; then
    sysroot_pkgconfig_dirs=(
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
    for dir in "${sysroot_pkgconfig_dirs[@]}"; do
      if [ -d "$dir" ]; then
        pkgconfig_dirs+=("$dir")
      fi
    done
  fi

  if [ -n "$old_pkg_config_libdir" ]; then
    IFS=':' read -r -a old_pkgconfig_dirs <<<"$old_pkg_config_libdir"
    pkgconfig_dirs+=("${old_pkgconfig_dirs[@]}")
  fi

  new_pkg_config_libdir=""
  if [ ${#pkgconfig_dirs[@]} -gt 0 ]; then
    new_pkg_config_libdir="${pkgconfig_dirs[0]}"
    for (( idx=1; idx<${#pkgconfig_dirs[@]}; idx++ )); do
      new_pkg_config_libdir="$new_pkg_config_libdir:${pkgconfig_dirs[$idx]}"
    done
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

  overlay_sysroot=""
  if [ -n "$sysroot" ]; then
    overlay_sysroot="$REPO_ROOT/$ARTIFACTS_DIR/pkgconfig-sysroots/$arch"
    rm -rf "$overlay_sysroot"
    mkdir -p "$overlay_sysroot"
    if [ -d "$sysroot" ]; then
      while IFS= read -r -d '' entry; do
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

  for stage_prefix in "${systemd_stage_prefixes[@]}"; do
    if [ -d "$stage_prefix" ]; then
      rel_path="${stage_prefix#/}"
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

  staged_lib_dirs=()
  staged_include_dirs=()
  for idx in "${!SYSTEMD_COMPONENTS[@]}"; do
    prefix="${systemd_stage_prefixes[$idx]}"
    for lib_dir in "$prefix/lib" "$prefix/lib64"; do
      if [ -d "$lib_dir" ]; then
        staged_lib_dirs+=("$lib_dir")
      fi
    done

    include_dir="$prefix/include"
    if [ -d "$include_dir" ]; then
      staged_include_dirs+=("$include_dir")
      if [ -n "$multiarch" ]; then
        multiarch_include_dir="$include_dir/$multiarch"
        if [ -d "$multiarch_include_dir" ]; then
          staged_include_dirs+=("$multiarch_include_dir")
        fi
      fi
    fi
  done

  if [ ${#staged_include_dirs[@]} -gt 0 ]; then
    staged_include_path="${staged_include_dirs[0]}"
    for (( idx=1; idx<${#staged_include_dirs[@]}; idx++ )); do
      staged_include_path="$staged_include_path:${staged_include_dirs[$idx]}"
    done

    old_c_include_path="${C_INCLUDE_PATH:-}"
    if [ -n "$old_c_include_path" ]; then
      export C_INCLUDE_PATH="$staged_include_path:$old_c_include_path"
    else
      export C_INCLUDE_PATH="$staged_include_path"
    fi

    old_cplus_include_path="${CPLUS_INCLUDE_PATH:-}"
    if [ -n "$old_cplus_include_path" ]; then
      export CPLUS_INCLUDE_PATH="$staged_include_path:$old_cplus_include_path"
    else
      export CPLUS_INCLUDE_PATH="$staged_include_path"
    fi

    old_cpath="${CPATH:-}"
    if [ -n "$old_cpath" ]; then
      export CPATH="$staged_include_path:$old_cpath"
    else
      export CPATH="$staged_include_path"
    fi
  fi

  if [ ${#staged_lib_dirs[@]} -gt 0 ]; then
    staged_lib_path="${staged_lib_dirs[0]}"
    for (( idx=1; idx<${#staged_lib_dirs[@]}; idx++ )); do
      staged_lib_path="$staged_lib_path:${staged_lib_dirs[$idx]}"
    done

    old_library_path="${LIBRARY_PATH:-}"
    if [ -n "$old_library_path" ]; then
      export LIBRARY_PATH="$staged_lib_path:$old_library_path"
    else
      export LIBRARY_PATH="$staged_lib_path"
    fi

    old_ld_library_path="${LD_LIBRARY_PATH:-}"
    if [ -n "$old_ld_library_path" ]; then
      export LD_LIBRARY_PATH="$staged_lib_path:$old_ld_library_path"
    else
      export LD_LIBRARY_PATH="$staged_lib_path"
    fi
  fi

  builddir="build-$arch"
  rm -rf "$builddir"
  mkdir -p "$builddir"
  cat > cross.txt <<CROSS_EOF
[binaries]
c = '${cross}gcc'
cpp = '${cross}g++'
ar = '${cross}ar'
strip = '${cross}strip'
pkgconfig = '${pkg_config_bin}'

[host_machine]
system = 'linux'
cpu_family = '${cpu}'
cpu = '${cpu}'
endian = 'little'
CROSS_EOF
  meson_setup_args=(
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
  DESTDIR="$out_dir/root" meson install -C "$builddir"
  cp "$out_dir/root/" "$out_dir/"
)

echo "$expected_version" > "$out_dir/VERSION"
