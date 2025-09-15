#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
L4RE_CORE_DIR="$REPO_ROOT/src/l4re-core"

# Determine which revision of l4re-core to check out. Precedence:
# 1. First script argument
# 2. L4RE_CORE_REV environment variable
# 3. Default to origin/master
L4RE_CORE_REV="${1:-${L4RE_CORE_REV:-origin/master}}"

git config --global --add safe.directory "$REPO_ROOT/src/l4re-core"
if [ ! -d "$L4RE_CORE_DIR/.git" ]; then
  git clone https://github.com/kernkonzept/l4re-core "$L4RE_CORE_DIR"
fi

(
  cd "$L4RE_CORE_DIR"
  git fetch
  git checkout "$L4RE_CORE_REV"
)
