#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
REPO=${CNB_REPO_SLUG:?CNB_REPO_SLUG is required}
COMMIT=${CNB_COMMIT:?CNB_COMMIT is required}
TOKEN=${CNB_TOKEN:?CNB_TOKEN is required}
API_ENDPOINT=${CNB_API_ENDPOINT:-https://api.cnb.cool}
ASSET_FILES=${ASSET_FILES:?ASSET_FILES is required}
DOWNLOAD_DIR=${1:?usage: cnb-download-commit-assets.sh DOWNLOAD_DIR}

[[ ! -e "$DOWNLOAD_DIR" ]] || { echo "download directory already exists: $DOWNLOAD_DIR" >&2; exit 1; }
mkdir -p "$(dirname "$DOWNLOAD_DIR")"
[[ ! -L "$DOWNLOAD_DIR" ]] || { echo 'download directory must not be a symlink' >&2; exit 1; }
staging=$(mktemp -d "${DOWNLOAD_DIR}.tmp.XXXXXX")
trap 'find "$staging" -depth -delete' EXIT

normalize_path() {
  local path=$1
  path=${path#./}
  [[ -n "$path" && "$path" != /* && "$path" != *'..'* && "$path" != *'\\'* ]] || {
    echo "invalid attachment path: $path" >&2
    exit 1
  }
  printf '%s\n' "$path"
}

IFS=',' read -r -a entries <<<"$ASSET_FILES"
[[ "${#entries[@]}" -gt 0 ]] || { echo 'no attachment files were exported' >&2; exit 1; }
for entry in "${entries[@]}"; do
  source_path=$(normalize_path "${entry//[[:space:]]/}")
  name=${source_path##*/}
  [[ "$name" != . && "$name" != .. && "$name" != */* && "$name" != *'\\'* ]] || {
    echo "invalid attachment name: $name" >&2
    exit 1
  }
  source_file="$ROOT_DIR/$source_path"
  [[ -f "$source_file" && ! -L "$source_file" ]] || {
    echo "uploaded source file is missing: $source_file" >&2
    exit 1
  }
  encoded_name=$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$name")
  downloaded="$staging/$name"
  curl --fail --silent --show-error --location \
    --header 'Accept: application/vnd.cnb.api+json' \
    --header "Authorization: Bearer $TOKEN" \
    "$API_ENDPOINT/$REPO/-/commit-assets/download/$COMMIT/$encoded_name" \
    -o "$downloaded"
  cmp "$source_file" "$downloaded"
  printf 'downloaded and reverified commit asset: %s\n' "$name"
done

mv -- "$staging" "$DOWNLOAD_DIR"
trap - EXIT
