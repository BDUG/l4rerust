#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="$SCRIPT_DIR/.."
DEFAULT_IMAGE_DIR="$REPO_ROOT/distribution"
DEFAULT_IMAGE_CANDIDATE="$DEFAULT_IMAGE_DIR/images/bootstrap_bash_arm_virt.elf"

IMAGE_PATH="${1:-}"

if [[ -z "$IMAGE_PATH" ]]; then
  if [[ -f "$DEFAULT_IMAGE_CANDIDATE" ]]; then
    IMAGE_PATH="$DEFAULT_IMAGE_CANDIDATE"
  else
    shopt -s nullglob
    images=("$DEFAULT_IMAGE_DIR"/images/*.elf)
    shopt -u nullglob

    if (( ${#images[@]} == 0 )); then
      echo "No bootable ELF image found under $DEFAULT_IMAGE_DIR/images." >&2
      echo "Build the project first (e.g. run scripts/build.sh) or provide an image path." >&2
      exit 1
    fi

    latest_image=""
    latest_mtime=0
    for candidate in "${images[@]}"; do
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
      echo "Unable to determine a bootable ELF image under $DEFAULT_IMAGE_DIR/images." >&2
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
