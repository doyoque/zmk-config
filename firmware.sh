#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Resolve the newest firmware ZIP downloaded by artifact.sh.

Usage:
  ./firmware.sh
  ./firmware.sh --dir build/artifacts
  ./firmware.sh --latest-link

Options:
  -d, --dir <dir>     Artifact directory (default: ./build/artifacts)
  -l, --latest-link   Prefer the latest.zip link if it exists
  -h, --help          Show this help
USAGE
}

ART_DIR="./build/artifacts"
USE_LATEST_LINK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)
      ART_DIR="$2"
      shift 2
      ;;
    -l|--latest-link)
      USE_LATEST_LINK=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$ART_DIR" ]]; then
  echo "Error: artifact directory not found: $ART_DIR" >&2
  exit 1
fi

if $USE_LATEST_LINK && [[ -L "$ART_DIR/latest.zip" || -f "$ART_DIR/latest.zip" ]]; then
  readlink -f "$ART_DIR/latest.zip"
  exit 0
fi

latest_zip="$(find "$ART_DIR" -type f -name '*.zip' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
if [[ -z "$latest_zip" ]]; then
  echo "Error: no ZIP files found in $ART_DIR" >&2
  exit 1
fi

printf '%s\n' "$latest_zip"
