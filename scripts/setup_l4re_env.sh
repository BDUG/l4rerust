#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common_build.sh
source "$SCRIPT_DIR/common_build.sh"

# Ensure l4re-core is present and up to date
"$SCRIPT_DIR/update_l4re_core.sh"

# Ensure the ham build tool is available
HAM_PATH="$SCRIPT_DIR/../ham"
HAM_BIN="$HAM_PATH/ham"
if [ ! -x "$HAM_BIN" ]; then
  echo "ham binary not found, fetching..."
  if [ ! -d "$HAM_PATH" ]; then
    git clone https://github.com/kernkonzept/ham.git "$HAM_PATH"
  fi
  if [ ! -x "$HAM_BIN" ]; then
    (cd "$HAM_PATH" && gmake >/dev/null 2>&1 || true)
  fi
fi

# The ham build from source depends on Perl modules that might not be available
# in minimal environments. Fall back to the official prebuilt binary if the
# required modules are missing so the script would not run successfully.
if ! perl -MGit::Repository -e1 >/dev/null 2>&1; then
  echo "Perl module Git::Repository missing, downloading prebuilt ham binary..."
  tmp_bin="${HAM_BIN}.tmp"
  if curl -fsSL "https://github.com/kernkonzept/ham/releases/latest/download/ham" -o "$tmp_bin"; then
    mv "$tmp_bin" "$HAM_BIN"
    chmod +x "$HAM_BIN"
  else
    rm -f "$tmp_bin"
    echo "Failed to download prebuilt ham. Install the Perl dependency 'Git::Repository' and rerun setup." >&2
    exit 1
  fi
fi

chmod +x "$HAM_BIN"
