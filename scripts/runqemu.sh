#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="$SCRIPT_DIR/.."
DEFAULT_IMAGE_DIR="$REPO_ROOT/distribution"
DEFAULT_ROOTFS_IMAGE="$DEFAULT_IMAGE_DIR/images/lsb_root.img"

usage() {
  cat <<'USAGE'
Usage: runqemu.sh [OPTIONS] [IMAGE]

Launch the most recent bootable image (or the IMAGE argument) in QEMU.

Options:
  -r, --rootfs PATH    Use PATH as the virtio-blk root filesystem image.
                       Defaults to distribution/images/lsb_root.img.
      --no-rootfs      Do not attach a root filesystem image.
  -h, --help           Show this help and exit.
  --                   Forward the remaining arguments directly to QEMU.
USAGE
}

ROOTFS_PATH=""
ATTACH_ROOTFS=true
USER_QEMU_ARGS=()
IMAGE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--rootfs)
      if [[ $# -lt 2 ]]; then
        echo "--rootfs requires a path argument" >&2
        usage >&2
        exit 1
      fi
      ROOTFS_PATH="$2"
      ATTACH_ROOTFS=true
      shift 2
      ;;
    --rootfs=*)
      ROOTFS_PATH="${1#*=}"
      ATTACH_ROOTFS=true
      shift
      ;;
    --no-rootfs)
      ROOTFS_PATH=""
      ATTACH_ROOTFS=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      USER_QEMU_ARGS=("$@")
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "${IMAGE_PATH:-}" ]]; then
        echo "Multiple image paths specified: '$IMAGE_PATH' and '$1'" >&2
        usage >&2
        exit 1
      fi
      IMAGE_PATH="$1"
      shift
      ;;
  esac
done

select_latest_image() {
  local latest_image=""
  local latest_mtime=0
  local candidate mtime

  for candidate in "$@"; do
    if [[ ! -e "$candidate" ]]; then
      continue
    fi

    if ! mtime=$(stat -c %Y "$candidate" 2>/dev/null); then
      if ! mtime=$(stat -f %m "$candidate" 2>/dev/null); then
        continue
      fi
    fi

    if (( mtime > latest_mtime )); then
      latest_mtime=$mtime
      latest_image="$candidate"
    fi
  done

  if [[ -z "$latest_image" ]]; then
    return 1
  fi

  printf '%s\n' "$latest_image"
}

shopt -s nullglob
bootstrap_images=("$DEFAULT_IMAGE_DIR"/images/bootstrap_vm-basic_*arm_virt*.uimage)
shopt -u nullglob

DEFAULT_IMAGE_CANDIDATE=""
if latest_bootstrap=$(select_latest_image "${bootstrap_images[@]}"); then
  DEFAULT_IMAGE_CANDIDATE="$latest_bootstrap"
fi

if [[ -z "$IMAGE_PATH" ]]; then
  if [[ -n "$DEFAULT_IMAGE_CANDIDATE" && -f "$DEFAULT_IMAGE_CANDIDATE" ]]; then
    IMAGE_PATH="$DEFAULT_IMAGE_CANDIDATE"
  else
    shopt -s nullglob
    images=("$DEFAULT_IMAGE_DIR"/images/*.elf "$DEFAULT_IMAGE_DIR"/images/*.uimage)
    shopt -u nullglob

    if (( ${#images[@]} == 0 )); then
      echo "No bootable ELF or U-Boot image (.elf or .uimage) found under $DEFAULT_IMAGE_DIR/images." >&2
      echo "Build the project first (e.g. run scripts/build.sh) or provide an image path." >&2
      exit 1
    fi

    if ! latest_image=$(select_latest_image "${images[@]}"); then
      echo "Unable to determine a bootable ELF or U-Boot image under $DEFAULT_IMAGE_DIR/images." >&2
      echo "Build the project first (e.g. run scripts/build.sh) or provide an image path." >&2
      exit 1
    fi

    IMAGE_PATH="$latest_image"
  fi
fi

if [[ ! -f "$IMAGE_PATH" ]]; then
  echo "Image '$IMAGE_PATH' does not exist." >&2
  echo "Build the project first (e.g. run scripts/build.sh) or provide a valid image path." >&2
  exit 1
fi

if [[ "$ATTACH_ROOTFS" == true ]]; then
  if [[ -z "$ROOTFS_PATH" ]]; then
    ROOTFS_PATH="$DEFAULT_ROOTFS_IMAGE"
  fi

  if [[ ! -f "$ROOTFS_PATH" ]]; then
    echo "Root filesystem image '$ROOTFS_PATH' does not exist." >&2
    echo "Run scripts/build.sh --components lsb_root or pass --no-rootfs to skip attaching it." >&2
    exit 1
  fi
fi

echo "Launching image: $IMAGE_PATH"

qemu_args=()
if [[ "$ATTACH_ROOTFS" == true ]]; then
  echo "Attaching root filesystem: $ROOTFS_PATH"
  qemu_args+=("-drive" "if=none,file=$ROOTFS_PATH,format=raw,id=lsb_root")
  qemu_args+=("-device" "virtio-blk-device,drive=lsb_root")
fi

if (( ${#USER_QEMU_ARGS[@]} )); then
  qemu_args+=("${USER_QEMU_ARGS[@]}")
fi

cmd=("$REPO_ROOT/src/l4/tool/bin/l4image" -i "$IMAGE_PATH" launch)

if (( ${#qemu_args[@]} )); then
  cmd+=(-- "${qemu_args[@]}")
fi

"${cmd[@]}"
