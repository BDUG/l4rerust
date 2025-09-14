#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
L4RE_CORE_DIR="$REPO_ROOT/src/l4re-core"

if [ ! -d "$L4RE_CORE_DIR/.git" ]; then
  git clone https://github.com/kernkonzept/l4re-core "$L4RE_CORE_DIR"
fi

(
  cd "$L4RE_CORE_DIR"
  git fetch
  git checkout origin/master
)
