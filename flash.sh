#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Flash firmware to NICENANO.

Usage:
  ./flash.sh l
  ./flash.sh r

Arguments:
  l    Flash firmware file containing "left"
  r    Flash firmware file containing "right"

Environment:
  FIRMWARE_DIR   Optional directory to search first for UF2 files
  ARTIFACT_DIR   Optional artifact directory (default: ./build/artifacts)
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

case "$1" in
  l) side="left" ;;
  r) side="right" ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Error: argument must be 'l' or 'r'." >&2
    usage >&2
    exit 1
    ;;
esac

require_cmd lsblk
require_cmd udisksctl
require_cmd find
require_cmd cp
require_cmd readlink

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artifact_dir="${ARTIFACT_DIR:-$script_dir/build/artifacts}"

resolve_latest_zip() {
  local dir="$1"
  local latest_link="$dir/latest.zip"

  [[ -d "$dir" ]] || return 1

  if [[ -L "$latest_link" || -f "$latest_link" ]]; then
    readlink -f "$latest_link"
    return 0
  fi

  find "$dir" -type f -name '*.zip' -printf '%T@ %p\n' \
    | sort -nr \
    | head -n1 \
    | cut -d' ' -f2-
}

search_dirs=()
if [[ -n "${FIRMWARE_DIR:-}" ]]; then
  search_dirs+=("$FIRMWARE_DIR")
fi

latest_zip="$(resolve_latest_zip "$artifact_dir" || true)"
if [[ -n "$latest_zip" ]]; then
  latest_zip_dir="$(dirname "$latest_zip")"
  search_dirs+=("$latest_zip_dir")
fi

search_dirs+=(
  "$script_dir/../firmware-artifact"
  "$script_dir/build"
  "$artifact_dir"
  "$HOME/Downloads"
)

find_firmware() {
  local pattern="$1"
  local dir
  local -a candidates=()
  local latest_ts=0
  local latest_file=""
  local ts

  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r file; do
      candidates+=("$file")
    done < <(find "$dir" -maxdepth 4 -type f -iname "*${pattern}*.uf2" 2>/dev/null)
  done

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  for file in "${candidates[@]}"; do
    ts="$(stat -c '%Y' "$file" 2>/dev/null || echo 0)"
    if (( ts > latest_ts )); then
      latest_ts="$ts"
      latest_file="$file"
    fi
  done

  if [[ -z "$latest_file" ]]; then
    return 1
  fi

  printf '%s\n' "$latest_file"
}

get_nicenano_dev() {
  lsblk -nrpo NAME,LABEL | awk '$2=="NICENANO"{print $1; exit}'
}

get_mountpoint_for_dev() {
  local dev="$1"
  lsblk -nrpo NAME,MOUNTPOINT | awk -v d="$dev" '$1==d{print $2; exit}'
}

src_file="$(find_firmware "$side")" || {
  echo "Error: could not find a .uf2 file containing '$side'." >&2
  echo "Searched in:" >&2
  for d in "${search_dirs[@]}"; do
    echo "  - $d" >&2
  done
  exit 1
}

dev="$(get_nicenano_dev)"
if [[ -z "$dev" ]]; then
  echo "Error: NICENANO device not found. Put board into bootloader mode first." >&2
  exit 1
fi

mountpoint="$(get_mountpoint_for_dev "$dev")"
if [[ -z "$mountpoint" ]]; then
  echo "Mounting $dev..."
  udisksctl mount -b "$dev" >/dev/null
  mountpoint="$(get_mountpoint_for_dev "$dev")"
fi

if [[ -z "$mountpoint" || ! -d "$mountpoint" ]]; then
  echo "Error: NICENANO mountpoint not available after mount attempt." >&2
  exit 1
fi

echo "Using firmware: $src_file"
if [[ -n "$latest_zip" ]]; then
  echo "Latest artifact ZIP: $latest_zip"
fi
echo "Target mount: $mountpoint"
echo "Copying to $mountpoint/CURRENT.uf2 ..."
cp -f "$src_file" "$mountpoint/CURRENT.uf2"
sync

sleep 1
if [[ -d "$mountpoint" ]]; then
  echo "Done. Firmware copied (mount is still present)."
else
  echo "Done. Board rebooted and unmounted (expected after UF2 flash)."
fi
