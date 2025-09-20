#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v dialog >/dev/null 2>&1; then
  echo "Error: the 'dialog' binary is required for the menu workflow." >&2
  exit 1
fi

run_driver_picker() {
  if command -v driver_picker >/dev/null 2>&1; then
    driver_picker "$@"
  else
    cargo run --quiet --manifest-path "$SCRIPT_DIR/driver_picker/Cargo.toml" -- "$@"
  fi
}

orig_args=("$@")
filtered_args=()
i=0
while [[ $i -lt ${#orig_args[@]} ]]; do
  arg=${orig_args[$i]}
  case "$arg" in
    --driver|--subsystem|--format)
      opt="$arg"
      ((i++))
      if [[ $i -ge ${#orig_args[@]} ]]; then
        echo "Missing value for $opt" >&2
        exit 1
      fi
      ((i++))
      ;;
    --driver=*|--subsystem=*|--format=*|--list|--list=*)
      ((i++))
      ;;
    *)
      filtered_args+=("$arg")
      ((i++))
      ;;
  esac
done

catalog=$(run_driver_picker --list --format tsv "${filtered_args[@]}")
if [[ -z "$catalog" ]]; then
  echo "No drivers discovered in the provided Linux source tree." >&2
  exit 1
fi

declare -A driver_map=()
declare -A subsystem_counts=()
subsystems=()
while IFS=$'\t' read -r subsystem driver; do
  [[ -z "$subsystem" || -z "$driver" ]] && continue
  if [[ -v driver_map["$subsystem"] ]]; then
    driver_map["$subsystem"]+=$'\n'"$driver"
  else
    driver_map["$subsystem"]="$driver"
    subsystems+=("$subsystem")
  fi
  count=${subsystem_counts["$subsystem"]:-0}
  subsystem_counts["$subsystem"]=$((count + 1))
done <<<"$catalog"

if [[ ${#subsystems[@]} -eq 0 ]]; then
  echo "No drivers discovered in the provided Linux source tree." >&2
  exit 1
fi

IFS=$'\n' subsystems=($(printf '%s\n' "${subsystems[@]}" | sort))
unset IFS

tmp_subsystem=$(mktemp)
tmp_driver=$(mktemp)
trap 'rm -f "$tmp_subsystem" "$tmp_driver"' EXIT

subsystem_menu=()
for subsystem in "${subsystems[@]}"; do
  count=${subsystem_counts["$subsystem"]}
  plural="driver"
  [[ $count -ne 1 ]] && plural="drivers"
  subsystem_menu+=("$subsystem" "$count $plural")
done

if ! dialog --clear --menu "Select subsystem" 20 70 15 "${subsystem_menu[@]}" 2>"$tmp_subsystem"; then
  status=$?
  if [[ $status -eq 1 || $status -eq 255 ]]; then
    echo "Selection cancelled." >&2
  fi
  exit $status
fi
selected_subsystem=$(<"$tmp_subsystem")

drivers_string=${driver_map["$selected_subsystem"]}
mapfile -t drivers < <(printf '%s\n' "$drivers_string" | sort)

driver_menu=()
for driver in "${drivers[@]}"; do
  driver_menu+=("$driver" "Linux config symbol")
done

if ! dialog --clear --menu "Select driver" 20 70 15 "${driver_menu[@]}" 2>"$tmp_driver"; then
  status=$?
  if [[ $status -eq 1 || $status -eq 255 ]]; then
    echo "Selection cancelled." >&2
  fi
  exit $status
fi
selected_driver=$(<"$tmp_driver")

run_driver_picker --driver "$selected_driver" --subsystem "$selected_subsystem" "${filtered_args[@]}"
