#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="$SCRIPT_DIR/.."

IMAGE_PATH="${1:-$REPO_ROOT/out/images/bootstrap_systemd_arm_virt.elf}"
"$REPO_ROOT/src/l4/tool/bin/l4image" -i "$IMAGE_PATH" launch
