#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Download firmware artifacts from a successful GitHub Actions run using gh.

Usage:
  ./artifact.sh [options]

Options:
  -r, --repo <owner/name>     GitHub repo (default: current repo)
  -w, --workflow <name|file>  Workflow name or file (default: build.yml)
  -b, --branch <branch>       Branch to filter latest successful run (default: all branches)
  -i, --run-id <id>           Specific run ID to download from
  -o, --out-dir <dir>         Subdirectory inside ./build (default: artifacts)
  -h, --help                  Show this help

Examples:
  ./artifact.sh
  ./artifact.sh --workflow build.yml --branch main
  ./artifact.sh --repo yourname/zmk-config --run-id 123456789 --out-dir my-fw
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

resolve_repo() {
  gh repo view --json nameWithOwner --jq '.nameWithOwner'
}

REPO=""
WORKFLOW="build.yml"
BRANCH=""
RUN_ID=""
BUILD_DIR="./build"
OUT_SUBDIR="artifacts"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--repo)
      REPO="$2"
      shift 2
      ;;
    -w|--workflow)
      WORKFLOW="$2"
      shift 2
      ;;
    -b|--branch)
      BRANCH="$2"
      shift 2
      ;;
    -i|--run-id)
      RUN_ID="$2"
      shift 2
      ;;
    -o|--out-dir)
      OUT_SUBDIR="$2"
      shift 2
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

require_cmd gh
require_cmd unzip

echo "Checking GitHub CLI auth..."
if ! gh auth status >/dev/null 2>&1; then
  echo "Error: gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  echo "Resolving repository from current directory..."
  REPO="$(resolve_repo)"
fi

mkdir -p "$BUILD_DIR"

# Force artifact output to stay under ./build
case "$OUT_SUBDIR" in
  ""|.|..|/*|../*|*/../*|*"/.."|*"../")
    echo "Error: --out-dir must be a safe subdirectory path inside ./build." >&2
    exit 1
    ;;
esac

OUT_DIR="$BUILD_DIR/$OUT_SUBDIR"
mkdir -p "$OUT_DIR"

ARTIFACT_NAMES=()

load_non_expired_artifacts() {
  local run_id="$1"
  mapfile -t ARTIFACT_NAMES < <(gh api \
    "repos/$REPO/actions/runs/$run_id/artifacts?per_page=100" \
    --paginate \
    --jq '.artifacts[] | select(.expired == false) | .name')
  [[ ${#ARTIFACT_NAMES[@]} -gt 0 ]]
}

find_latest_run_with_artifacts() {
  local branch_filter="$1"
  local scope_label="$2"
  local -a list_cmd
  local -a candidate_run_ids

  list_cmd=(gh run list
    --repo "$REPO"
    --workflow "$WORKFLOW"
    --status success
    --limit 100
    --json databaseId,createdAt)

  if [[ -n "$branch_filter" ]]; then
    list_cmd+=(--branch "$branch_filter")
  fi

  mapfile -t candidate_run_ids < <("${list_cmd[@]}" --jq 'sort_by(.createdAt) | reverse | .[] | .databaseId')

  if [[ ${#candidate_run_ids[@]} -eq 0 ]]; then
    return 1
  fi

  echo "Searching successful runs with available artifacts ($scope_label)..."
  for candidate in "${candidate_run_ids[@]}"; do
    if load_non_expired_artifacts "$candidate"; then
      RUN_ID="$candidate"
      return 0
    fi
  done

  return 1
}

if [[ -z "$RUN_ID" ]]; then
  if [[ -n "$BRANCH" ]]; then
    if ! find_latest_run_with_artifacts "$BRANCH" "branch: $BRANCH"; then
      echo "No usable artifacts found on branch '$BRANCH'. Trying all branches..."
      if ! find_latest_run_with_artifacts "" "all branches"; then
        echo "Error: no successful runs with non-expired artifacts found for workflow '$WORKFLOW' in '$REPO'." >&2
        echo "Hint: trigger a new workflow run, then re-run this script." >&2
        exit 1
      fi
    fi
  else
    if ! find_latest_run_with_artifacts "" "all branches"; then
      echo "Error: no successful runs with non-expired artifacts found for workflow '$WORKFLOW' in '$REPO'." >&2
      echo "Hint: trigger a new workflow run, then re-run this script." >&2
      exit 1
    fi
  fi
else
  if ! load_non_expired_artifacts "$RUN_ID"; then
    echo "Error: run $RUN_ID has no non-expired artifacts." >&2
    echo "Hint: use a newer run ID or trigger a new workflow run." >&2
    exit 1
  fi
fi

echo "Using run ID: $RUN_ID"

echo "Cleaning old firmware archives in: $OUT_DIR"
deleted_count="$(find "$OUT_DIR" -type f \( -name '*.uf2' -o -name '*.zip' \) -print -delete | wc -l | tr -d '[:space:]')"
if [[ "$deleted_count" -gt 0 ]]; then
  echo "Removed $deleted_count existing file(s) matching *.uf2 or *.zip."
else
  echo "No existing *.uf2 or *.zip files found."
fi

echo "Downloading ${#ARTIFACT_NAMES[@]} artifacts to: $OUT_DIR"
for name in "${ARTIFACT_NAMES[@]}"; do
  target_dir="$OUT_DIR/$name"
  mkdir -p "$target_dir"
  echo "- $name -> $target_dir"
  gh run download "$RUN_ID" \
    --repo "$REPO" \
    --name "$name" \
    --dir "$target_dir"

  mapfile -t zip_files < <(find "$target_dir" -type f -name '*.zip')
  if [[ ${#zip_files[@]} -gt 0 ]]; then
    echo "  Extracting ${#zip_files[@]} zip file(s) in $target_dir"
    for zip_file in "${zip_files[@]}"; do
      unzip -o -q "$zip_file" -d "$(dirname "$zip_file")"
    done
  fi
done

echo "Done. Artifacts downloaded under: $OUT_DIR"
