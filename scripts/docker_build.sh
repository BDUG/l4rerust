#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

# Ensure l4re-core is present and up to date
"$SCRIPT_DIR/update_l4re_core.sh"

# Ensure the ham build tool is available
HAM_PATH="$(realpath "$SCRIPT_DIR/../ham")"
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

# Use ham to keep the manifest consistent with the latest l4re-core
(
  cd "$REPO_ROOT/src" &&
  "$HAM_BIN" init -u https://github.com/kernkonzept/manifest.git &&
  "$HAM_BIN" sync l4re-core
)

IMAGE="l4rerust-builder"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build -t "$IMAGE" -f docker/Dockerfile .
fi

# Create a named container so we can copy build artifacts out afterwards.
container="l4rerust-build-$$"

# Create container without bind mounts to enforce copy-out semantics.
echo "Create build container ..."
docker create --name "$container" -w /workspace "$IMAGE" "$@" >/dev/null

# Copy the repository into the container.
docker cp . "$container:/workspace"

# Run the build and capture the exit status.
build_status=0
echo "Start build container ..."
docker start -a "$container" || build_status=$?

# Copy the generated artifacts back to the host.
host_out="$REPO_ROOT/out"
# rm -rf "$host_out"
# `docker cp` works even on stopped containers, so we can attempt to copy
# artifacts directly without needing to exec into the container first. We
# suppress `docker cp`'s own error output and use the exit status to detect
# whether any artifacts were produced.
if docker cp "$container:/workspace/out" "$host_out" >/dev/null 2>&1; then
  echo "Build artifacts were generated."
else
  echo "No build artifacts were generated."
fi

echo "Build done ..."
# Clean up the container regardless of success.
#docker logs --tail 50 "$container" 
#docker rm "$container" >/dev/null

exit $build_status
