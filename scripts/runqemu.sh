#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="$SCRIPT_DIR/.."
DEFAULT_IMAGE_DIR="$REPO_ROOT/distribution"

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

IMAGE_PATH="${1:-}"

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

echo "Launching image: $IMAGE_PATH"

"$REPO_ROOT/src/l4/tool/bin/l4image" -i "$IMAGE_PATH" launch
