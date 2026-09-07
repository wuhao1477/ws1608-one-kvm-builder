#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/scripts/cnb-ci-env.sh"
ASSET_DIR=${1:?usage: cnb-upload-commit-assets.sh ASSET_DIR}
REPO=${CNB_REPO_SLUG:?CNB_REPO_SLUG is required}
COMMIT=${CNB_COMMIT:?CNB_COMMIT is required}
TTL=${CNB_ASSET_TTL:-14}
[[ -d "$ASSET_DIR" && ! -L "$ASSET_DIR" ]] || { echo 'invalid asset directory' >&2; exit 1; }
TMP_DIR=$(mktemp -d)
trap 'find "$TMP_DIR" -depth -delete' EXIT

for file in "$ASSET_DIR"/*; do
  [[ -f "$file" && ! -L "$file" ]] || continue
  name=${file##*/}
  [[ "$name" != . && "$name" != .. && "$name" != */* && "$name" != *'\\'* ]] || exit 1
  size=$(wc -c <"$file" | tr -d ' ')
  response=$(cnb git post-commit-asset-upload-url --repo "$REPO" --sha1 "$COMMIT" \
    --asset-name "$name" --size "$size" --ttl "$TTL" --verbose 2>/dev/null)
  upload_url=$(jq -er '.data.upload_url' <<<"$response")
  verify_url=$(jq -er '.data.verify_url' <<<"$response")
  curl --fail --silent --show-error --request PUT \
    --header 'Content-Type: application/octet-stream' --upload-file "$file" "$upload_url"
  confirmation=$(printf '%s' "$verify_url" | sed -E 's#^.*/asset-upload-confirmation/([^/]+)/(.+)$#\1\t\2#')
  upload_token=${confirmation%%$'\t'*}
  asset_path=${confirmation#*$'\t'}
  cnb git post-commit-asset-upload-confirmation --repo "$REPO" --sha1 "$COMMIT" \
    --upload-token "$upload_token" --asset-path "$asset_path" --ttl "$TTL" >/dev/null

  downloaded="$TMP_DIR/$name"
  curl --fail --silent --show-error --location \
    -H "Authorization: Bearer ${CNB_TOKEN:?CNB_TOKEN is required}" \
    "$CNB_API_ENDPOINT/$REPO/-/commit-assets/download/$COMMIT/$name?share=true" -o "$downloaded"
  cmp "$file" "$downloaded"
  printf 'uploaded and reverified commit asset: %s\n' "$name"
done
