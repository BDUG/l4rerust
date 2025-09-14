#!/usr/bin/env bash
set -euo pipefail

echo "Entering build container"
trap 'echo "Leaving build container"' EXIT

SCRIPT_DIR="$(dirname "$0")"
# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"

detect_cross_compilers
validate_tools

"$SCRIPT_DIR/build_arm.sh" "$@"
