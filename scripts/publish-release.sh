#!/usr/bin/env bash
set -Eeuo pipefail

BUILD_TAG=${BUILD_TAG:?BUILD_TAG is required}
BUILD_STAMP=${BUILD_STAMP:?BUILD_STAMP is required}
ONE_KVM_VERSION=${ONE_KVM_VERSION:?ONE_KVM_VERSION is required}
UPSTREAM_TAG=${UPSTREAM_TAG:?UPSTREAM_TAG is required}
IMAGE_NAME=${IMAGE_NAME:?IMAGE_NAME is required}
ARTIFACT_DIR=${ARTIFACT_DIR:?ARTIFACT_DIR is required}
RELEASE_NOTES_FILE=${RELEASE_NOTES_FILE:?RELEASE_NOTES_FILE is required}
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}
GITHUB_SHA=${GITHUB_SHA:?GITHUB_SHA is required}

for command in gh jq sha256sum basename; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done

assets=(
  "$ARTIFACT_DIR/$IMAGE_NAME"
  "$ARTIFACT_DIR/$IMAGE_NAME.xz"
  "$ARTIFACT_DIR/SHA256SUMS"
  "$ARTIFACT_DIR/manifest.json"
)
for asset in "${assets[@]}"; do
  [[ -f "$asset" ]] || { echo "missing release asset: $asset" >&2; exit 1; }
done

if gh release view "$BUILD_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  echo "refusing to overwrite existing Release: $BUILD_TAG" >&2
  exit 1
fi
if gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$BUILD_TAG" >/dev/null 2>&1; then
  echo "refusing to overwrite existing tag: $BUILD_TAG" >&2
  exit 1
fi

draft_created=false
published=false
cleanup_release() {
  local status=$?
  trap - EXIT
  if [[ "$draft_created" == true && "$published" != true ]]; then
    gh release delete "$BUILD_TAG" --repo "$GITHUB_REPOSITORY" --yes --cleanup-tag >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup_release EXIT

verify_remote_assets() {
  local expected_draft=$1
  local release_json
  release_json=$(gh release view "$BUILD_TAG" --repo "$GITHUB_REPOSITORY" \
    --json tagName,isDraft,isPrerelease,assets)
  [[ "$(jq -r '.tagName' <<<"$release_json")" == "$BUILD_TAG" ]]
  [[ "$(jq -r '.isDraft' <<<"$release_json")" == "$expected_draft" ]]
  [[ "$(jq -r '.isPrerelease' <<<"$release_json")" == false ]]
  [[ "$(jq '.assets | length' <<<"$release_json")" -eq "${#assets[@]}" ]]
  for asset in "${assets[@]}"; do
    local name expected actual state
    name=$(basename "$asset")
    expected="sha256:$(sha256sum "$asset" | awk '{print $1}')"
    actual=$(jq -er --arg name "$name" '.assets[] | select(.name == $name) | .digest' <<<"$release_json")
    state=$(jq -er --arg name "$name" '.assets[] | select(.name == $name) | .state' <<<"$release_json")
    [[ "$state" == uploaded ]]
    [[ "$actual" == "$expected" ]] || {
      echo "remote digest mismatch for $name: expected $expected, got $actual" >&2
      return 1
    }
  done
}

release_title="WS1608 One-KVM $ONE_KVM_VERSION ($UPSTREAM_TAG, ${BUILD_STAMP}Z)"
draft_created=true
gh release create "$BUILD_TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --draft \
  --target "$GITHUB_SHA" \
  --title "$release_title" \
  --notes-file "$RELEASE_NOTES_FILE" \
  "${assets[@]}"

verify_remote_assets true

gh release edit "$BUILD_TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --draft=false \
  --latest \
  --title "$release_title" \
  --notes-file "$RELEASE_NOTES_FILE"

verify_remote_assets false
published=true
trap - EXIT
echo "Published immutable Release $BUILD_TAG"
