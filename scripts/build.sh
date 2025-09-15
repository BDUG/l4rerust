#!/usr/bin/env bash
set -euo pipefail

echo "Entering build container"
trap 'echo "Leaving build container"' EXIT

SCRIPT_DIR="$(dirname "$0")"
# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"

# Set up the L4Re environment (l4re-core and ham)
"$SCRIPT_DIR/setup_l4re_env.sh"
HAM_BIN="$(resolve_path "$SCRIPT_DIR/../ham/ham")"

# Use ham to keep the manifest consistent with the latest l4re-core
(
  cd "$SCRIPT_DIR/../src" &&
  "$HAM_BIN" init -u https://github.com/kernkonzept/manifest.git &&
  "$HAM_BIN" sync l4re-core
)

detect_cross_compilers
validate_tools

"$SCRIPT_DIR/build_arm.sh" "$@"
