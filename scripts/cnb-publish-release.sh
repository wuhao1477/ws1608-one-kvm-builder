#!/usr/bin/env bash
set -Eeuo pipefail

REPO=${CNB_REPO_SLUG:?CNB_REPO_SLUG is required}
RELEASE_TAG=${RELEASE_TAG:?RELEASE_TAG is required}
RELEASE_NAME=${RELEASE_NAME:?RELEASE_NAME is required}
RELEASE_COMMIT=${RELEASE_COMMIT:?RELEASE_COMMIT is required}
RELEASE_NOTES_FILE=${RELEASE_NOTES_FILE:?RELEASE_NOTES_FILE is required}
RELEASE_ASSET_DIR=${RELEASE_ASSET_DIR:?RELEASE_ASSET_DIR is required}
RELEASE_PRERELEASE=${RELEASE_PRERELEASE:-false}
RELEASE_LATEST=${RELEASE_LATEST:-false}
RELEASE_ASSET_TTL=${RELEASE_ASSET_TTL:-0}

[[ "$RELEASE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'invalid release tag' >&2; exit 1; }
[[ "$RELEASE_PRERELEASE" == true || "$RELEASE_PRERELEASE" == false ]] || exit 1
[[ "$RELEASE_LATEST" == true || "$RELEASE_LATEST" == false ]] || exit 1
[[ -f "$RELEASE_NOTES_FILE" && ! -L "$RELEASE_NOTES_FILE" ]] || exit 1
[[ -d "$RELEASE_ASSET_DIR" && ! -L "$RELEASE_ASSET_DIR" ]] || exit 1

existing=$(cnb releases get-release-by-tag --repo "$REPO" --tag "$RELEASE_TAG" --verbose 2>/dev/null || true)
if [[ "$(jq -r '.status // 0' <<<"$existing")" == 200 ]]; then
  echo "refusing to overwrite existing CNB Release: $RELEASE_TAG" >&2
  exit 1
fi

assets=()
while IFS= read -r file; do
  name=${file##*/}
  [[ "$name" != */* && "$name" != *'\\'* && "$name" != . && "$name" != .. ]] || exit 1
  [[ -s "$file" && ! -L "$file" ]] || { echo "invalid release asset: $file" >&2; exit 1; }
  assets+=("$file")
done < <(find "$RELEASE_ASSET_DIR" -mindepth 1 -maxdepth 1 -type f -print | sort)
[[ "${#assets[@]}" -gt 0 ]] || { echo 'release has no assets' >&2; exit 1; }

release_id=''
tag_created=false
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$status" -ne 0 && -n "$release_id" ]]; then
    cnb releases delete-release --repo "$REPO" --release-id "$release_id" >/dev/null 2>&1 || true
  fi
  if [[ "$status" -ne 0 && "$tag_created" == true ]]; then
    cnb git delete-tag --repo "$REPO" --tag "$RELEASE_TAG" >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT

if [[ "$RELEASE_PRERELEASE" == true ]]; then
  release_json=$(cnb releases post-release --repo "$REPO" --tag-name "$RELEASE_TAG" \
    --target-commitish "$RELEASE_COMMIT" --name "$RELEASE_NAME" \
    --body-file "$RELEASE_NOTES_FILE" --draft --prerelease \
    --make-latest "$RELEASE_LATEST" --verbose)
else
  release_json=$(cnb releases post-release --repo "$REPO" --tag-name "$RELEASE_TAG" \
    --target-commitish "$RELEASE_COMMIT" --name "$RELEASE_NAME" \
    --body-file "$RELEASE_NOTES_FILE" --draft \
    --make-latest "$RELEASE_LATEST" --verbose)
fi
release_id=$(jq -er '.data.id' <<<"$release_json")
tag_created=true

for file in "${assets[@]}"; do
  name=${file##*/}
  size=$(wc -c <"$file" | tr -d ' ')
  upload_json=$(cnb releases post-release-asset-upload-url --repo "$REPO" \
    --release-id "$release_id" --asset-name "$name" --size "$size" \
    --ttl "$RELEASE_ASSET_TTL" --verbose)
  upload_url=$(jq -er '.data.upload_url' <<<"$upload_json")
  verify_url=$(jq -er '.data.verify_url' <<<"$upload_json")
  curl --fail --silent --show-error --request PUT \
    --header 'Content-Type: application/octet-stream' --upload-file "$file" "$upload_url"
  confirmation=$(printf '%s' "$verify_url" | sed -E 's#^.*/asset-upload-confirmation/([^/]+)/(.+)$#\1\t\2#')
  upload_token=${confirmation%%$'\t'*}
  asset_path=${confirmation#*$'\t'}
  cnb releases post-release-asset-upload-confirmation --repo "$REPO" \
    --release-id "$release_id" --upload-token "$upload_token" \
    --asset-path "$asset_path" --ttl "$RELEASE_ASSET_TTL" >/dev/null
  printf 'uploaded release asset: %s\n' "$name"
done

patch_data=$(jq -cn --argjson prerelease "$RELEASE_PRERELEASE" '{draft:false, prerelease:$prerelease}')
cnb releases patch-release --repo "$REPO" --release-id "$release_id" --data "$patch_data" >/dev/null

published=$(cnb releases get-release-by-tag --repo "$REPO" --tag "$RELEASE_TAG" --verbose)
[[ "$(jq -r '.data.draft' <<<"$published")" == false ]] || exit 1
[[ "$(jq -r '.data.prerelease' <<<"$published")" == "$RELEASE_PRERELEASE" ]] || exit 1
[[ "$(jq '.data.assets | length' <<<"$published")" -eq "${#assets[@]}" ]] || exit 1
for file in "${assets[@]}"; do
  name=${file##*/}
  expected=$(sha256sum "$file" | awk '{print $1}')
  actual=$(jq -er --arg name "$name" '.data.assets[] | select(.name == $name) | .hash_value' <<<"$published")
  [[ "$actual" == "$expected" ]] || { echo "asset digest mismatch: $name" >&2; exit 1; }
done

trap - EXIT
printf 'published CNB Release %s\n' "$RELEASE_TAG"
