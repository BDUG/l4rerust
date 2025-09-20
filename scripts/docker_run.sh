#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

HOST_WORKSPACE="${REPO_ROOT}"
DOCKER_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)
            shift
            HOST_WORKSPACE="${1:?--workspace requires a path}"
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: docker_run.sh [--workspace PATH] [docker run args...]

Options:
  --workspace PATH  Host directory to mount at /workspace inside the container.
                    Defaults to the repository root.
EOF
            exit 0
            ;;
        *)
            DOCKER_ARGS+=("$1")
            shift
            ;;
    esac
done

HOST_WORKSPACE="$(realpath "${HOST_WORKSPACE}")"

docker run --rm -it -v "${HOST_WORKSPACE}:/workspace" -w /workspace l4rerust-builder "${DOCKER_ARGS[@]}"

