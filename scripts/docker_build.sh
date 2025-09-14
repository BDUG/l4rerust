#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

# Ensure l4re-core is present and up to date
"$SCRIPT_DIR/update_l4re_core.sh"

IMAGE="l4rerust-builder"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build -t "$IMAGE" -f docker/Dockerfile .
fi

# Create a named container so we can copy build artifacts out afterwards.
container="l4rerust-build-$$"

# Create container without bind mounts to enforce copy-out semantics.
docker create --name "$container" -w /workspace "$IMAGE" "$@" >/dev/null

# Copy the repository into the container.
docker cp . "$container:/workspace"

# Run the build and capture the exit status.
build_status=0
docker start -a "$container" || build_status=$?

# Copy the generated artifacts back to the host.
host_out="$REPO_ROOT/out"
rm -rf "$host_out"
# `docker cp` works even on stopped containers, so we can attempt to copy
# artifacts directly without needing to exec into the container first. We
# suppress `docker cp`'s own error output and use the exit status to detect
# whether any artifacts were produced.
if docker cp "$container:/workspace/out" "$host_out" >/dev/null 2>&1; then
  :
else
  echo "No build artifacts were generated."
fi

# Clean up the container regardless of success.
docker rm "$container" >/dev/null

exit $build_status
