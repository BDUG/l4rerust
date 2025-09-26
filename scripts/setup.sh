#! /bin/bash

# This scripts sets up a snapshot on the target build machine.

set -e

# Source shared build helpers.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/common_build.sh
source "$SCRIPT_DIR/common_build.sh"
REPO_ROOT="$(resolve_path "$SCRIPT_DIR/..")"
cd "$REPO_ROOT"

# Handle optional non-interactive mode which runs both config and setup in
# one go. When invoked as `scripts/setup.sh --non-interactive` the script will skip
# prompts and execute the combined steps automatically.
cmd="$1"
non_interactive=0
if [ "$cmd" = "--non-interactive" ]; then
  non_interactive=1
  cmd="all"
fi

if [ "$cmd" != "clean" ]; then
  "$SCRIPT_DIR/setup_l4re_env.sh"

  if ! command -v ham >/dev/null 2>&1; then
    HAM_BIN="$(resolve_path "$SCRIPT_DIR/../ham/ham")"
    if [ -x "$HAM_BIN" ]; then
      PATH="$(dirname "$HAM_BIN"):$PATH"
      export PATH
    else
      echo "ham binary missing after setup" >&2
      exit 1
    fi
  fi

  (
    cd "$SCRIPT_DIR/../src" || exit 1

    if [ ! -d .ham ] || [ ! -f .ham/manifests_json ]; then
      ham init -u https://github.com/kernkonzept/manifest.git
    else
      echo "ham manifest already initialized, skipping init"
    fi

    if ham sync l4re-core fiasco; then
      :
    else
      sync_status=$?
      fiasco_dir="fiasco"
      l4_dir="l4"
      l4re_core_dir="l4re-core"
      if [ -d "$fiasco_dir" ] && { [ -d "$l4_dir" ] || [ -d "$l4re_core_dir" ]; }; then
        missing_artifacts=()

        if [ ! -f "$fiasco_dir/Makefile" ]; then
          missing_artifacts+=("src/$fiasco_dir/Makefile")
        fi

        l4_root=""
        if [ -d "$l4_dir" ]; then
          l4_root="$l4_dir"
        elif [ -d "$l4re_core_dir/src/l4" ]; then
          l4_root="$l4re_core_dir/src/l4"
        fi

        if [ -n "$l4_root" ]; then
          for artifact in Makefile conf/Makeconf mk/Makeconf; do
            if [ ! -e "$l4_root/$artifact" ]; then
              missing_artifacts+=("src/$l4_root/$artifact")
            fi
          done
        else
          missing_artifacts+=("src/$l4_dir")
        fi

        if [ ${#missing_artifacts[@]} -eq 0 ]; then
          echo "ham sync reported failure but components already installed, skipping."
        else
          echo "ERROR: ham sync failed and required artifacts are missing:" >&2
          for artifact in "${missing_artifacts[@]}"; do
            echo "  - $artifact" >&2
          done
          echo "The previous ham run did not finish successfully. Please resolve the sync issue and rerun ham." >&2
          exit "$sync_status"
        fi
      else
        exit "$sync_status"
      fi
    fi

    fiasco_patch_dir="$SCRIPT_DIR/patches/fiasco"
    if [ -d "$fiasco_patch_dir" ] && [ -d fiasco ]; then
      (
        cd fiasco
        for patch_file in "$fiasco_patch_dir"/*.patch; do
          [ -e "$patch_file" ] || continue
          patch -p1 -N <"$patch_file"
        done
      )
    fi
  )
fi

# check we're in the right directory when needed
if [ "$cmd" != "clean" ] && [ ! -d src/l4 ]; then
  echo "Call setup as ./$(basename $0) in the right directory"
  exit 1
fi

if [ -n "$SYSTEM" ]; then
  echo "SYSTEM environment variable set, not good"
  exit 1
fi

if [ "$cmd" != "clean" ] && [ "$non_interactive" -eq 0 ]; then
  if [ -n "$CROSS_COMPILE" ]; then
    read -p "Cross-compiler prefix (CROSS_COMPILE) [$CROSS_COMPILE]: " tmp
    CROSS_COMPILE=${tmp:-$CROSS_COMPILE}
  else
    read -p "Cross-compiler prefix (CROSS_COMPILE): " CROSS_COMPILE
  fi
fi

export CROSS_COMPILE=${CROSS_COMPILE:-}
CC=${CC:-${CROSS_COMPILE}g++}
CXX=${CXX:-${CROSS_COMPILE}g++}
LD=${LD:-${CROSS_COMPILE}ld}

add_to_config()
{
  echo "$@" >> obj/.config
}

write_config()
{
  # write out config, fresh version
  mkdir -p obj
  echo '# snapshot build configuration' > obj/.config

  for c in CONF_DO_ARM \
           CONF_DO_ARM_VIRT_PL2 \
           CONF_DO_ARM64 \
           CONF_DO_ARM64_VIRT_EL2 \
           CONF_FAILED_ARM \
           CONF_FAILED_ARM64 \
           CROSS_COMPILE_ARM \
           CROSS_COMPILE_ARM64 \
  ; do
    local v=$(eval echo \$$c)
    [ -n "$v" ] && add_to_config $c="$v"
  done

  return 0
}

clean_directory_except()
{
  local dir="$1"
  shift

  if [ ! -d "$dir" ]; then
    return 0
  fi

  local nullglob_was_set=0
  local dotglob_was_set=0
  if shopt -q nullglob; then
    nullglob_was_set=1
  fi
  if shopt -q dotglob; then
    dotglob_was_set=1
  fi
  shopt -s nullglob dotglob

  local entry
  local base
  local preserve
  local should_preserve
  for entry in "$dir"/*; do
    base="$(basename "$entry")"
    should_preserve=false
    for preserve in "$@"; do
      if [ "$base" = "$preserve" ]; then
        should_preserve=true
        break
      fi
    done
    if [ "$should_preserve" = false ]; then
      rm -rf "$entry"
    fi
  done

  if [ "$nullglob_was_set" -eq 0 ]; then
    shopt -u nullglob
  fi
  if [ "$dotglob_was_set" -eq 0 ]; then
    shopt -u dotglob
  fi
}

clean_lsb_root_directory()
{
  local lsb_root_dir="config/lsb_root"

  if [ ! -d "$lsb_root_dir" ]; then
    return
  fi

  # Remove any top-level entries other than the README placeholder and the
  # tracked lib directory that holds service definitions.
  clean_directory_except "$lsb_root_dir" README lib

  local lib_dir="$lsb_root_dir/lib"
  if [ ! -d "$lib_dir" ]; then
    return
  fi

  # Drop everything under lib/ except for the systemd hierarchy we keep under
  # version control.
  clean_directory_except "$lib_dir" systemd

  local systemd_dir="$lib_dir/systemd"
  if [ ! -d "$systemd_dir" ]; then
    return
  fi

  # Prune entries under lib/systemd that are not part of the tracked
  # lib/systemd/system subtree.
  clean_directory_except "$systemd_dir" system

  local systemd_units_dir="$systemd_dir/system"
  if [ ! -d "$systemd_units_dir" ]; then
    return
  fi

  local -a preserved_units=()
  if [ -d "config/systemd" ]; then
    local unit_path
    local unit_name
    for unit_path in config/systemd/*; do
      [ -e "$unit_path" ] || continue
      unit_name="$(basename "$unit_path")"
      local already_present=false
      local existing
      for existing in "${preserved_units[@]}"; do
        if [ "$existing" = "$unit_name" ]; then
          already_present=true
          break
        fi
      done
      if [ "$already_present" = false ]; then
        preserved_units+=("$unit_name")
      fi
    done
  fi

  if command -v git >/dev/null 2>&1 &&
     git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local tracked_path
    local tracked_name
    while IFS= read -r tracked_path; do
      [ -n "$tracked_path" ] || continue
      tracked_name="$(basename "$tracked_path")"
      local already_present=false
      local existing
      for existing in "${preserved_units[@]}"; do
        if [ "$existing" = "$tracked_name" ]; then
          already_present=true
          break
        fi
      done
      if [ "$already_present" = false ]; then
        preserved_units+=("$tracked_name")
      fi
    done < <(git ls-files -- "$systemd_units_dir" 2>/dev/null || true)
  fi

  clean_directory_except "$systemd_units_dir" "${preserved_units[@]}"
}

clean_rust_artifacts()
{
  local repo_root="${REPO_ROOT:-$(pwd)}"
  local -a search_roots=(
    "$repo_root/src"
    "$repo_root/crates"
    "$repo_root/tools"
  )

  local root
  for root in "${search_roots[@]}"; do
    [ -d "$root" ] || continue

    while IFS= read -r -d '' lock_file; do
      if [ "$lock_file" != "$repo_root/Cargo.lock" ]; then
        rm -f "$lock_file"
      fi
    done < <(find "$root" -type f -name Cargo.lock -print0)

    while IFS= read -r -d '' target_dir; do
      rm -rf "$target_dir"
    done < <(find "$root" -type d -name target -print0)
  done
}

do_clean()
{
  # Remove build artifacts and staged directories created by the build scripts
  rm -rf obj
  rm -rf out distribution
  rm -rf config/pkg_staging
  clean_rust_artifacts
  clean_lsb_root_directory
}

do_config()
{
  if [ -n "$SETUP_CONFIG_ALL" ]; then
    CONF_DO_ARM=1
    CONF_DO_ARM64=1

    CONF_DO_ARM_VIRT_PL2=1
    CONF_DO_ARM_RPIZ=0
    CONF_DO_ARM_RPI3=0
    CONF_DO_ARM_RPI4=0
    CONF_DO_ARM_IMX6UL_PL1=0
    CONF_DO_ARM_IMX6UL_PL2=0
    CONF_DO_ARM64_VIRT_EL2=0
    CONF_DO_ARM64_RCAR3=0
    CONF_DO_ARM64_RPI3=0
    CONF_DO_ARM64_RPI4=0
    CONF_DO_ARM64_S32=0
    CONF_DO_ARM64_ZYNQMP=0

    detect_cross_compilers

    write_config
    return 0;
  fi


  if command -v dialog; then

    tmpfile=$(mktemp)
    trap "rm -f $tmpfile" 0 1 2 5 15

    dialog \
      --visit-items \
      --begin 2 10 \
	--infobox \
	 "The list of choices represents a popular set of target platforms.  Many more are available." \
	 5 60 \
      --and-widget --begin 9 10 \
        --checklist "Select Targets to build:" 12 60 5 \
         arm       "ARM (platform selection follows)"          off \
         arm64     "ARM64 / AARCH64"                           off \
         mips      "MIPS"                                      off \
         2> $tmpfile

    result=$(cat $tmpfile)

    if [ -z "$result" ]; then
      echo
      echo "ERROR: You did not select any platform."
      echo "ERROR: Please do so by running 'gmake setup' again."
      echo
      exit 1
    fi


    for e in $result; do
      # fixup for older dialogs
      [ "${e#\"}" = "$e" ] && e="\"$e\""
      case "$e" in
	\"arm\") CONF_DO_ARM=1 ;;
	\"arm64\") CONF_DO_ARM64=1 ;;
      esac
    done

    if [ -n "$CONF_DO_ARM" ]; then
      dialog \
	--visit-items \
	--begin 2 10 \
	  --infobox \
	   "The list of choices represents a popular set of target platforms. Many more are available." \
	   5 60 \
	--and-widget --begin 9 10 \
	  --checklist "Select ARM Targets to build:" 12 60 5 \
	   arm-virt-pl2    "QEMU Virt Platform"  on \
	   arm-rpiz        "Raspberry Pi Zero"   off \
	   arm-rpi3        "Raspberry Pi 3"      off \
	   arm-rpi4        "Raspberry Pi 4"      off \
	   arm-imx6ul-pl1  "NXP i.MX6UL/ULL"     off \
	   arm-imx6ul-pl2  "NXP i.MX6UL/ULL Virtualization" off \
	   2> $tmpfile

      result=$(cat $tmpfile)

      for e in $result; do
	# fixup for older dialogs
	[ "${e#\"}" = "$e" ] && e="\"$e\""
	case "$e" in
	  \"arm-virt-pl2\")   CONF_DO_ARM_VIRT_PL2=1 ;;
	  \"arm-rpiz\")       CONF_DO_ARM_RPIZ=1 ;;
	  \"arm-rpi3\")       CONF_DO_ARM_RPI3=1 ;;
	  \"arm-rpi4\")       CONF_DO_ARM_RPI4=1 ;;
	  \"arm-imx6ul-pl1\") CONF_DO_ARM_IMX6UL_PL1=1 ;;
	  \"arm-imx6ul-pl2\") CONF_DO_ARM_IMX6UL_PL2=1 ;;
	esac
      done
    fi

    if [ -n "$CONF_DO_ARM64" ]; then
      dialog \
	--visit-items \
	--begin 2 10 \
	  --infobox \
	   "The list of choices represents a popular set of target platforms. Many more are available." \
	   5 60 \
	--and-widget --begin 9 10 \
	  --checklist "Select ARM Targets to build:" 11 60 4 \
	   arm64-virt-el2  "QEMU Virt Platform"  on \
	   arm64-rpi3      "Raspberry Pi 3"      off \
	   arm64-rpi4      "Raspberry Pi 4"      off \
	   arm64-s32       "Renesas R-Car 3"     off \
	   arm64-s32       "NXP S32"             off \
	   arm64-zynqmp    "Xilinx ZynqMP"       off \
	   2> $tmpfile

      result=$(cat $tmpfile)

      for e in $result; do
	# fixup for older dialogs
	[ "${e#\"}" = "$e" ] && e="\"$e\""
	case "$e" in
	  \"arm64-virt-el2\") CONF_DO_ARM64_VIRT_EL2=1 ;;
	  \"arm64-rcar3\")    CONF_DO_ARM64_RCAR3=1 ;;
	  \"arm64-rpi3\")     CONF_DO_ARM64_RPI3=1 ;;
	  \"arm64-rpi4\")     CONF_DO_ARM64_RPI4=1 ;;
	  \"arm64-s32\")      CONF_DO_ARM64_S32=1 ;;
	  \"arm64-zynqmp\")   CONF_DO_ARM64_ZYNQMP=1 ;;
	esac
      done
    fi

    if [ -n "$CONF_DO_MIPS" ]; then
      dialog \
	--begin 2 10 \
	  --infobox \
	   "Please choose which MIPS little-endian variant to build." \
	   5 60 \
	--and-widget --begin 9 10 \
	  --checklist "Select MIPS variant to build:" 11 60 4 \
	   mips32r2    "MIPS32r2" off \
	   mips32r6    "MIPS32r6" off \
	   mips64r2    "MIPS64r2" off \
	   mips64r6    "MIPS64r6" off \
	   2> $tmpfile

      result=$(cat $tmpfile)
      for e in $result; do
	[ "${e#\"}" = "$e" ] && e="\"$e\""
	case "$e" in
	  \"mips32r2\") CONF_DO_MIPS32R2=1 ;;
	  \"mips32r6\") CONF_DO_MIPS32R6=1 ;;
	  \"mips64r2\") CONF_DO_MIPS64R2=1 ;;
	  \"mips64r6\") CONF_DO_MIPS64R6=1 ;;
	esac
      done
    fi

    if [ -n "$CONF_DO_ARM" ]; then
      dialog --no-mouse --visit-items \
	--inputbox "ARM cross compiler prefix (CROSS_COMPILE)" 8 70 "arm-linux-gnueabihf-" \
	2> $tmpfile
      CROSS_COMPILE_ARM=$(cat $tmpfile)
    fi

    if [ -n "$CONF_DO_ARM64" ]; then
      dialog --no-mouse --visit-items \
	--inputbox "AARCH64 cross compiler prefix (CROSS_COMPILE)" 8 70 "aarch64-elf-" \
	2> $tmpfile
      CROSS_COMPILE_ARM64=$(cat $tmpfile)
    fi

    if [ -n "$CONF_DO_MIPS32R2" ]; then
      dialog --no-mouse --visit-items \
	--inputbox "MIPS el-32r2 cross compiler prefix (CROSS_COMPILE)" 8 70 "mips-linux-" \
	2> $tmpfile
      CROSS_COMPILE_MIPS32R2=$(cat $tmpfile)
    fi
    if [ -n "$CONF_DO_MIPS32R6" ]; then
      dialog --no-mouse --visit-items \
	--inputbox "MIPS el-32r6 cross compiler prefix (CROSS_COMPILE)" 8 70 "mips-linux-" \
	2> $tmpfile
      CROSS_COMPILE_MIPS32R6=$(cat $tmpfile)
    fi

    if [ -n "$CONF_DO_MIPS64R2" ]; then
      dialog --no-mouse --visit-items \
	--inputbox "MIPS el-64r2 cross compiler prefix (CROSS_COMPILE)" 8 70 "mips-linux-" \
	2> $tmpfile
      CROSS_COMPILE_MIPS64R2=$(cat $tmpfile)
    fi
    if [ -n "$CONF_DO_MIPS64R6" ]; then
      dialog --no-mouse --visit-items \
	--inputbox "MIPS el-64r6 cross compiler prefix (CROSS_COMPILE)" 8 70 "mips-linux-" \
	2> $tmpfile
      CROSS_COMPILE_MIPS64R6=$(cat $tmpfile)
    fi

  else
    echo "'dialog' program not found, aborting."
    echo "Install dialog and issue 'gmake setup' again."
    exit 1
  fi

  write_config
  return 0;
}

###########################################################

load_config()
{
  if [ ! -e obj/.config ]; then
    echo "Configuration missing, not configured?!"
    exit 1
  fi

  . obj/.config
}

redo_config()
{
  if [ -n "$CONF_FAILED_ARM" ]; then
    unset CONF_DO_ARM
    add_to_config "unset CONF_DO_ARM"
    unset CONF_DO_ARM_VIRT_PL2
    unset CONF_DO_ARM_RPIZ
    unset CONF_DO_ARM_RPI3
    unset CONF_DO_ARM_RPI4
    unset CONF_DO_ARM_IMX6UL_PL1
    unset CONF_DO_ARM_IMX6UL_PL2
  fi

  if [ -n "$CONF_FAILED_UX" ]; then
    unset CONF_DO_UX
    add_to_config "unset CONF_DO_UX"
  fi

  if [ -n "$CONF_FAILED_MIPS32R2" ]; then
    unset CONF_DO_MIPS32R2
    add_to_config "unset CONF_DO_MIPS32R2"
  fi

  if [ -n "$CONF_FAILED_MIPS32R6" ]; then
    unset CONF_DO_MIPS32R6
    add_to_config "unset CONF_DO_MIPS32R6"
  fi

  if [ -n "$CONF_FAILED_MIPS64R2" ]; then
    unset CONF_DO_MIPS64R2
    add_to_config "unset CONF_DO_MIPS64R2"
  fi

  if [ -n "$CONF_FAILED_MIPS64R6" ]; then
    unset CONF_DO_MIPS64R6
    add_to_config "unset CONF_DO_MIPS64R6"
  fi
}

check_cc()
{
  if [ -n "$1" ]; then
    if echo 'int main(void) { return 0; }' | $1 $2 -c -x c - -o /dev/null; then
      return 0
    fi
  else
    echo "Invalid compiler command given"
  fi
  return 1
}

check_eabi_gxx()
{
  # probably half-hearted approach but well
  [ -z "$1" ] && return 1
  $1 -E -dD -x c++ /dev/null | grep -qw __ARM_EABI__
}

check_tool()
{
  command -v $1 > /dev/null
  if ! command -v $1 > /dev/null;  then
    return 1
  fi

  case "$1" in
    *gcc|*g++)
      check_cc "$1" "$2"
      return $?
    ;;
    gmake|*ld)
      $1 -v > /dev/null 2>&1
      return $?
    ;;
    *cpp|*nm)
      $1 --help > /dev/null 2>&1
      return $?
    ;;
    gawk)
      $1 --help > /dev/null 2>&1
      return $?
    ;;
    perl)
      $1 -V > /dev/null 2>&1
      return $?
    ;;
    doxygen)
      doxygen | grep "Doxygen ver" > /dev/null 2>&1
      return $?
    ;;
    qemu-system-arm)
      $1 -h > /dev/null 2>&1
      return $?
    ;;
    *)
      echo "Unknown tool $1"
      return 1
    ;;
  esac
}

#exchange_kconfig_choice()
#{
#  kconfigfile=$1
#  disablesym=$2
#  enablesym=$3
#
#  perl -p -i \
#       -e "s/$disablesym=y/# $disablesym is not set/; s/# $enablesym is not set/$enablesym=y/" \
#       $kconfigfile
#}

#switch_to_kconfig_setup_arm()
#{
#  exchange_kconfig_choice $1 CONFIG_PLATFORM_TYPE_rv $2
#  exchange_kconfig_choice $1 CONFIG_CPU_ARM_ARMV5TE $3
#}

Makeconf_added_gen=()
Makeconf_added_qemu_std=()

add_gen()
{
  for f in "${Makeconf_added_gen[@]}"; do
    [ "$f" = "$1" ] && return
  done
  if [ -z "$REMOTE" ]; then
    echo "QEMU_OPTIONS += -vnc :4" >> "$1"
  fi

  echo 'QEMU_OPTIONS += $(QEMU_OPTIONS-$(PLATFORM_TYPE))' >> "$1"
  echo 'MODULE_SEARCH_PATH += $(MODULE_SEARCH_PATH-$(PLATFORM_TYPE))' >> "$1"
  Makeconf_added_gen+=("$1")
}

append_qemu_option()
{
  local file="$1"
  local option="$2"

  if [ -f "$file" ] && grep -F -q -- "$option" "$file"; then
    return
  fi

  echo "QEMU_OPTIONS += $option" >> "$file"
}

add_std_qemu_options()
{
  for f in "${Makeconf_added_qemu_std[@]}"; do
    [ "$f" = "$1" ] && { add_gen "$1"; return; }
  done
  append_qemu_option "$1" "-display none"
  append_qemu_option "$1" "-serial stdio"
  append_qemu_option "$1" "-monitor none"
  Makeconf_added_qemu_std+=("$1")

  add_gen "$1"
}

add_nonx86_qemu_options()
{
  add_gen "$1"
}

check_cross_tools()
{
  name=$1
  confvar=$2
  confvarfailed=$3
  cross_compile=$4

  if [ -n "$confvar" ]; then
    echo "Checking for needed cross programs and tools for $name"
    tools_needed="${cross_compile}g++ ${cross_compile}cpp ${cross_compile}nm ${cross_compile}ld"
    unset failed
    for t in $tools_needed; do
      result="ok"
      if ! check_tool $t; then
        result="Not found or FAILED, disabling $name builds"
        eval $confvarfailed=1
	failed=1
      fi
      printf "%15s ... %s\n" $t "$result"
      if [ -n "$failed" ]; then
	break
      fi
    done
  fi
}

check_tools()
{
# Generic tools
  echo "Checking for needed programs and tools"
  tools_needed="gmake ${CC} ${CXX} ld gawk perl"
  for t in $tools_needed; do
    result="ok"
    if ! check_tool $t; then
      result="NOT DETECTED"
      command_missing="$command_missing $t"
    fi
    printf "%15s ... %s\n" $t "$result"
  done
  echo
  if [ -n "$command_missing" ]; then
    echo "Some command is missing on your system."
    echo "Please install it before continuing with 'gmake setup':"
    echo "   $command_missing"
    do_clean
    exit 1
  fi

  check_cross_tools "ARM"      "$CONF_DO_ARM"      CONF_FAILED_ARM      "$CROSS_COMPILE_ARM"
  check_cross_tools "ARM64"    "$CONF_DO_ARM64"    CONF_FAILED_ARM64    "$CROSS_COMPILE_ARM64"

  if [ -n "$CONF_DO_UX" ]; then
    echo "Checking some specific Fiasco-UX build thing on 64bit platforms"
    if ! echo "#include <sys/cdefs.h>" | ${CC} -m32 -x c -c -o /dev/null - > /dev/null 2>&1; then
      result="Failed, disabling Fiasco-UX builds"
      CONF_FAILED_UX=1
    else
      result="ok"
    fi
    printf "%15s ... %s\n" "UX build" "$result"
  fi
  echo

# Optional tools
  echo "Checking optional programs and tools"
  tools_optional="doxygen"
  [ "$CONF_DO_ARM" ] && tools_needed="$tools_needed qemu-system-arm"
  for t in $tools_optional; do
    result="ok"
    if ! check_tool $t; then
      result="NOT DETECTED but optional"
      command_missing="$command_missing $t"
    fi
    printf "%15s ... %s\n" $t "$result"
  done
  echo
  if [ -n "$command_missing" ]; then
    echo "Some optional command is missing on your system, don't worry."
    echo "   $command_missing"
    echo
  fi
}

do_setup()
{
  [ "$CONF_DO_ARM_VIRT_PL2" ] && fiasco_configs="$fiasco_configs arm-virt-pl2"
  [ "$CONF_DO_ARM64_VIRT_EL2" ] && fiasco_configs="$fiasco_configs arm64-virt-el2"

  get_fiasco_dir()
  {
    case "$1" in
      arm64-virt-el2) echo "arm64-virt-el2" ;;
      arm-virt-pl2) echo "arm-virt-pl2" ;;
      *) return 1 ;;
    esac
  }

  get_cross_compile()
  {
    case "$1" in
      arm64-virt-el2|arm64-rcar3|arm64-rpi3|arm64-rpi4|arm64-s32|arm64-zynqmp)
        echo "$CROSS_COMPILE_ARM64" ;;
      arm-virt-pl2|arm-rpiz|arm-rpi3|arm-rpi4|arm-imx6ul|arm-imx6ul-pl2)
        echo "$CROSS_COMPILE_ARM" ;;
      *) return 1 ;;
    esac
  }

  echo "Creating build directories..."

  mkdir -p obj/fiasco
  mkdir -p obj/l4
  mkdir -p obj/l4linux

  echo "Linux directory"
  
  [ -e src/l4linux ] && l4lx_avail=1

  echo "Fiasco build dirs"
  # Fiasco build dirs
  for b in $fiasco_configs; do
    fiasco_dir=$(get_fiasco_dir "$b") || {
      echo "Internal error: No directory given for config '$b'"
      exit 1
    }
    cross_compile=$(get_cross_compile "$b")
    echo "$fiasco_dir" "->" "$b"
    if [ -z "$cross_compile" ]; then
      echo "Internal error: No cross compiler given for config '$b'"
      exit 1
    fi

    build_dir="obj/fiasco/$fiasco_dir"
    makeconf_local="$build_dir/Makeconf.local"

    if [ -d "$build_dir" ]; then
      if [ -f "$build_dir/Makefile" ]; then
        echo "Fiasco build dir '$build_dir' already exists, skipping creation."
      else
        echo "Fiasco build dir '$build_dir' exists but is incomplete, recreating it."
        rm -rf "$build_dir"
      fi
    fi

    if [ ! -d "$build_dir" ]; then
      (cd src/fiasco && gmake B=../../"$build_dir" T="$b")
    fi

    if [ ! -d "$build_dir" ]; then
      echo "ERROR: Failed to prepare Fiasco build directory '$build_dir'" >&2
      exit 1
    fi

    if [ -f "$makeconf_local" ]; then
      sed -i \
        -e '/^CROSS_COMPILE=/d' \
        -e '/^CONFIG_HOST_CC=/d' \
        -e '/^CONFIG_HOST_CXX=/d' \
        -e '/^HOST_CC[[:space:]]*:?=/d' \
        -e '/^HOST_CXX[[:space:]]*:?=/d' \
        "$makeconf_local"
    fi

    host_cc=${HOST_CC:-$(command -v cc || command -v gcc || true)}
    host_cxx=${HOST_CXX:-$(command -v c++ || command -v g++ || true)}

    if [ -z "$host_cc" ] || [ -z "$host_cxx" ]; then
      echo "Missing host compiler toolchain (cc/c++) required for Fiasco build" >&2
      exit 1
    fi

    {
      printf 'CROSS_COMPILE="%s"\n' "$cross_compile"
      printf 'CONFIG_HOST_CC="%s"\n' "$host_cc"
      printf 'CONFIG_HOST_CXX="%s"\n' "$host_cxx"
    } >> "$makeconf_local"
  done

  echo "Default dirs"
  
  # L4Re build dirs with default configs
  if [ "$CONF_DO_ARM" ]; then
    gmake -C src/l4 CROSS_COMPILE=$CROSS_COMPILE_ARM \
      DEFCONFIG=mk/defconfig/config.arm-rv-v7a B=../../obj/l4/arm-v7
    gmake -C obj/l4/arm-v7 CROSS_COMPILE=$CROSS_COMPILE_ARM oldconfig
    ARM_L4_DIR_FOR_LX_MP=obj/l4/arm-v7
    echo CROSS_COMPILE=$CROSS_COMPILE_ARM >> obj/l4/arm-v7/Makeconf.local
  fi

  if [ "$CONF_DO_ARM64" ]; then
    gmake -C src/l4 CROSS_COMPILE=$CROSS_COMPILE_ARM64 DEFCONFIG=mk/defconfig/config.arm64-rv-v8a B=../../obj/l4/arm64
  fi


  # L4Linux build setup
  [ -z "$ARM_L4_DIR_FOR_LX_UP" ] && ARM_L4_DIR_FOR_LX_UP=$ARM_L4_DIR_FOR_LX_MP

  if [ -n "$ARM_L4_DIR_FOR_LX_UP" -a -n "$l4lx_avail" ]; then

    mkdir -p obj/l4linux/arm-up

    if [ "$ARM_L4_DIR_FOR_LX_MP" ]; then
      mkdir -p obj/l4linux/arm-mp
    fi

    if ! check_eabi_gxx ${CROSS_COMPILE_ARM}g++; then
      echo "WARNING: L4Linux has been disabled due to a detected old OABI compiler"
      echo "WARNING: Please update your compiler to an EABI version"
      add_to_config SKIP_L4LINUX_ARM_BUILD=1
    fi
  fi

  common_paths=$(pwd)/config:$(pwd)/config/cfg:$(pwd)/src/l4/conf:$(pwd)/src/l4/conf/examples

  if [ "$CONF_DO_ARM" ]; then
    local odir=obj/l4/arm-v7
    local Mboot=$odir/conf/Makeconf.boot
    mkdir -p $odir/conf

    if [ "$CONF_DO_ARM_VIRT_PL2" ]; then
      echo "MODULE_SEARCH_PATH+=$(pwd)/obj/fiasco/arm-virt-pl2:$(pwd)/obj/l4linux/arm-mp:$common_paths" >> $Mboot
      cat<<EOF >> $Mboot
QEMU_OPTIONS-arm_virt += -M virt,virtualization=true -m 1024 -cpu cortex-a15 -smp 2
EOF
      echo "ENTRY=hello        BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm-virt-pl2" >> $odir/.imagebuilds
      echo "ENTRY=bash         BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm-virt-pl2" >> $odir/.imagebuilds
      echo "ENTRY=hello-shared BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm-virt-pl2" >> $odir/.imagebuilds
      echo "ENTRY=vm-basic     BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm-virt-pl2" >> $odir/.imagebuilds
      echo "ENTRY=vm-multi     BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm-virt-pl2" >> $odir/.imagebuilds
    fi

    add_std_qemu_options $Mboot
    add_nonx86_qemu_options $Mboot
  fi # ARM


  echo "ABC ##############"

  if [ "$CONF_DO_ARM64" ]; then
    local odir=obj/l4/arm64
    local Mboot=$odir/conf/Makeconf.boot
    mkdir -p $odir/conf

    echo "MODULE_SEARCH_PATH+=\$(PATH_FIASCO):$common_paths" >> $Mboot

    if [ "$CONF_DO_ARM64_VIRT_EL2" ]; then
      cat<<EOF >> $Mboot
QEMU_OPTIONS-arm_virt += -M virt,virtualization=true -m 1024 -cpu cortex-a57 -smp 2
EOF
      echo "ENTRY=hello        BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm64-virt-el2" >> $odir/.imagebuilds
      echo "ENTRY=bash         BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm64-virt-el2" >> $odir/.imagebuilds
      echo "ENTRY=hello-shared BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm64-virt-el2" >> $odir/.imagebuilds
      echo "ENTRY=vm-basic     BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm64-virt-el2" >> $odir/.imagebuilds
      echo "ENTRY=vm-multi     BOOTSTRAP_IMAGE_SUFFIX=arm_virt PT=arm_virt PATH_FIASCO=$(pwd)/obj/fiasco/arm64-virt-el2" >> $odir/.imagebuilds
    fi


    add_std_qemu_options $Mboot
    add_nonx86_qemu_options $Mboot

  fi # ARM64

}


case "$cmd" in
  config)
     do_config
     ;;
  setup)
     load_config
     check_tools
     redo_config
     do_setup
     ;;
  all)
     SETUP_CONFIG_ALL=${SETUP_CONFIG_ALL:-1}
     do_config
     load_config
     check_tools
     redo_config
     do_setup
     ;;
  clean)
     do_clean
     ;;
  *)
     echo "Call $0 [config|setup|clean|--non-interactive]"
     exit 1
     ;;
esac

exit 0
