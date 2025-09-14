#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

docker run --rm -it -v "${REPO_ROOT}:/workspace" -w /workspace l4rerust-builder "$@"

