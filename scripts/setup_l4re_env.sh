#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"

# Ensure l4re-core is present and up to date
"$SCRIPT_DIR/update_l4re_core.sh"

# Ensure the ham build tool is available
HAM_PATH="$(resolve_path "$SCRIPT_DIR/../ham")"
HAM_BIN="$HAM_PATH/ham"
if [ ! -x "$HAM_BIN" ]; then
  echo "ham binary not found, fetching..."
  if [ ! -d "$HAM_PATH" ]; then
    git clone https://github.com/kernkonzept/ham.git "$HAM_PATH"
  fi
  if [ ! -x "$HAM_BIN" ]; then
    (cd "$HAM_PATH" && gmake >/dev/null 2>&1 || true)
  fi
  if [ ! -x "$HAM_BIN" ]; then
    curl -L "https://github.com/kernkonzept/ham/releases/latest/download/ham" -o "$HAM_BIN"
  fi
  chmod +x "$HAM_BIN"
fi
