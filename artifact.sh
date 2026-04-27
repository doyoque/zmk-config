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

trim() {
  local value="$1"
  # Remove leading and trailing whitespace.
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
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
if gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI auth: OK"
else
  if [[ -n "${GH_TOKEN:-}" || -n "${GITHUB_TOKEN:-}" ]]; then
    echo "GitHub CLI auth status unavailable, but token environment variable detected. Continuing..."
  else
    echo "GitHub CLI is not authenticated. Continuing anyway (public repos may still work)."
    echo "If later requests fail with auth errors, run: gh auth login" >&2
  fi
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
RUN_HEAD_SHA=""
RUN_HEAD_MESSAGE=""

load_non_expired_artifacts() {
  local run_id="$1"
  mapfile -t ARTIFACT_NAMES < <(gh api \
    "repos/$REPO/actions/runs/$run_id/artifacts?per_page=100" \
    --paginate \
    --jq '.artifacts[] | select(.expired == false) | .name')
  [[ ${#ARTIFACT_NAMES[@]} -gt 0 ]]
}

load_run_commit_info() {
  local run_id="$1"
  local commit_info
  commit_info="$(gh run view "$run_id" \
    --repo "$REPO" \
    --json headSha,displayTitle \
    --jq '[.headSha, .displayTitle] | @tsv')"

  RUN_HEAD_SHA="$(printf '%s' "$commit_info" | cut -f1)"
  RUN_HEAD_MESSAGE="$(printf '%s' "$commit_info" | cut -f2-)"
}

prompt_with_default() {
  local prompt_text="$1"
  local default_value="$2"
  local user_value
  local trimmed_value

  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt_text [$default_value]: " user_value
  else
    read -r -p "$prompt_text: " user_value
  fi

  trimmed_value="$(trim "$user_value")"
  if [[ -z "$trimmed_value" ]]; then
    printf '%s' "$default_value"
  else
    printf '%s' "$trimmed_value"
  fi
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
load_run_commit_info "$RUN_ID"

BUILD_COMMIT_HASH=""
BUILD_COMMIT_MESSAGE=""

if [[ -t 0 ]]; then
  BUILD_COMMIT_HASH="$(prompt_with_default "Enter build commit hash" "$RUN_HEAD_SHA")"
  BUILD_COMMIT_MESSAGE="$(prompt_with_default "Enter build commit message" "$RUN_HEAD_MESSAGE")"
else
  BUILD_COMMIT_HASH="$RUN_HEAD_SHA"
  BUILD_COMMIT_MESSAGE="$RUN_HEAD_MESSAGE"
fi

BUILD_COMMIT_HASH="$(trim "$BUILD_COMMIT_HASH")"
BUILD_COMMIT_MESSAGE="$(trim "$BUILD_COMMIT_MESSAGE")"

if [[ -z "$BUILD_COMMIT_HASH" ]]; then
  echo "Error: commit hash is required." >&2
  exit 1
fi

if [[ ! "$BUILD_COMMIT_HASH" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
  echo "Error: commit hash must be 7-40 hexadecimal characters." >&2
  exit 1
fi

if [[ -z "$BUILD_COMMIT_MESSAGE" ]]; then
  echo "Error: commit message is required." >&2
  exit 1
fi

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

metadata_file="$OUT_DIR/build-info.txt"
cat >"$metadata_file" <<EOF
repo: $REPO
workflow: $WORKFLOW
run_id: $RUN_ID
build_commit_hash: $BUILD_COMMIT_HASH
build_commit_message: $BUILD_COMMIT_MESSAGE
downloaded_at_utc: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "Saved build metadata to: $metadata_file"
echo "Done. Artifacts downloaded under: $OUT_DIR"
