#!/usr/bin/env bash
set -Eeuo pipefail

BUILD_TAG=${BUILD_TAG:?BUILD_TAG is required}
BUILD_NUMBER=${BUILD_NUMBER:?BUILD_NUMBER is required}
BUILD_REVISION=${BUILD_REVISION:?BUILD_REVISION is required}
BUILDER_COMMIT=${BUILDER_COMMIT:?BUILDER_COMMIT is required}
ONE_KVM_VERSION=${ONE_KVM_VERSION:?ONE_KVM_VERSION is required}
UPSTREAM_TAG=${UPSTREAM_TAG:?UPSTREAM_TAG is required}
PACKAGE_DIGEST=${PACKAGE_DIGEST:?PACKAGE_DIGEST is required}
IMAGE_NAME=${IMAGE_NAME:?IMAGE_NAME is required}
ARTIFACT_DIR=${ARTIFACT_DIR:?ARTIFACT_DIR is required}
RELEASE_NOTES_FILE=${RELEASE_NOTES_FILE:?RELEASE_NOTES_FILE is required}
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}

for command in awk cp gh grep jq mktemp sha256sum; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done
[[ "$BUILD_TAG" =~ ^[A-Za-z0-9._-]+$ && "$BUILD_TAG" == *"-$BUILD_REVISION" ]] || {
  echo "invalid build tag: $BUILD_TAG" >&2
  exit 1
}
[[ "$BUILDER_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo 'invalid builder commit' >&2; exit 1; }
[[ "$PACKAGE_DIGEST" =~ ^[0-9a-f]{64}$ ]] || { echo 'invalid package digest' >&2; exit 1; }
[[ -d "$ARTIFACT_DIR" && ! -L "$ARTIFACT_DIR" ]] || { echo 'invalid artifact directory' >&2; exit 1; }
[[ -f "$RELEASE_NOTES_FILE" && ! -L "$RELEASE_NOTES_FILE" ]] || { echo 'invalid release notes file' >&2; exit 1; }

case "$IMAGE_NAME" in
  ''|.|..|*/*|*\\*) echo "IMAGE_NAME is not a basename: $IMAGE_NAME" >&2; exit 1 ;;
esac
assets=(
  "$ARTIFACT_DIR/$IMAGE_NAME"
  "$ARTIFACT_DIR/$IMAGE_NAME.xz"
  "$ARTIFACT_DIR/SHA256SUMS"
  "$ARTIFACT_DIR/manifest.json"
  "$ARTIFACT_DIR/validation-report.json"
)
for asset in "${assets[@]}"; do
  [[ -f "$asset" && ! -L "$asset" && -s "$asset" ]] || {
    echo "invalid release asset: $asset" >&2
    exit 1
  }
done

if gh release view "$BUILD_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  echo "refusing to overwrite existing Release: $BUILD_TAG" >&2
  exit 1
fi
if gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$BUILD_TAG" >/dev/null 2>&1; then
  echo "refusing to overwrite existing tag: $BUILD_TAG" >&2
  exit 1
fi

notes_file=$(mktemp)
cp "$RELEASE_NOTES_FILE" "$notes_file"
digest() { sha256sum "$1" | awk '{print $1}'; }
{
  printf '\none_kvm_version=%s\n' "$ONE_KVM_VERSION"
  printf 'one_kvm_release=%s\n' "$UPSTREAM_TAG"
  printf 'package_sha256=%s\n' "$PACKAGE_DIGEST"
  printf 'build_number=%s\n' "$BUILD_NUMBER"
  printf 'build_revision=%s\n' "$BUILD_REVISION"
  printf 'build_tag=%s\n' "$BUILD_TAG"
  printf 'builder_commit=%s\n' "$BUILDER_COMMIT"
  printf 'image_name=%s\n' "$IMAGE_NAME"
  printf 'compressed_image_name=%s\n' "$IMAGE_NAME.xz"
  printf 'checksums_name=SHA256SUMS\n'
  printf 'manifest_name=manifest.json\n'
  printf 'validation_report_name=validation-report.json\n'
  printf 'image_sha256=%s\n' "$(digest "${assets[0]}")"
  printf 'compressed_image_sha256=%s\n' "$(digest "${assets[1]}")"
  printf 'checksums_sha256=%s\n' "$(digest "${assets[2]}")"
  printf 'manifest_sha256=%s\n' "$(digest "${assets[3]}")"
  printf 'validation_report_sha256=%s\n' "$(digest "${assets[4]}")"
} >> "$notes_file"

tag_created=false
release_created=false
release_id=''
cleanup_on_exit() {
  local status=$?
  trap - EXIT
  if [[ "$status" -ne 0 ]]; then
    if [[ "$release_created" == true ]]; then
      if [[ -n "$release_id" ]]; then
        gh api --method DELETE "repos/$GITHUB_REPOSITORY/releases/$release_id" >/dev/null 2>&1 || true
      else
        gh release delete "$BUILD_TAG" --repo "$GITHUB_REPOSITORY" --yes >/dev/null 2>&1 || true
      fi
    fi
    if [[ "$tag_created" == true ]]; then
      gh api --method DELETE "repos/$GITHUB_REPOSITORY/git/refs/tags/$BUILD_TAG" >/dev/null 2>&1 || true
    fi
  fi
  rm -f -- "$notes_file"
  exit "$status"
}
trap cleanup_on_exit EXIT

gh api --method POST "repos/$GITHUB_REPOSITORY/git/refs" \
  --raw-field "ref=refs/tags/$BUILD_TAG" \
  --raw-field "sha=$BUILDER_COMMIT" >/dev/null
tag_created=true
tag_commit=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$BUILD_TAG" | jq -er '.object.sha')
[[ "$tag_commit" == "$BUILDER_COMMIT" ]] || { echo 'reserved tag points to the wrong commit' >&2; exit 1; }

release_title="WS1608 One-KVM Rust $ONE_KVM_VERSION ($UPSTREAM_TAG, $BUILD_REVISION)"
release_json=$(gh api --method POST "repos/$GITHUB_REPOSITORY/releases" \
  --raw-field "tag_name=$BUILD_TAG" \
  --raw-field "target_commitish=$BUILDER_COMMIT" \
  --raw-field "name=$release_title" \
  --raw-field "body=$(<"$notes_file")" \
  -F draft=true \
  -F prerelease=false)
release_created=true
release_id=$(jq -er '.id' <<<"$release_json")
gh release upload "$BUILD_TAG" --repo "$GITHUB_REPOSITORY" "${assets[@]}"

verify_remote_assets() {
  local expected_draft=$1 release
  release=$(gh release view "$BUILD_TAG" --repo "$GITHUB_REPOSITORY" \
    --json tagName,isDraft,isPrerelease,assets,body)
  [[ $(jq -r '.tagName' <<<"$release") == "$BUILD_TAG" ]]
  [[ $(jq -r '.isDraft' <<<"$release") == "$expected_draft" ]]
  [[ $(jq -r '.isPrerelease' <<<"$release") == false ]]
  [[ $(jq '.assets | length' <<<"$release") -eq ${#assets[@]} ]]
  local body
  body=$(jq -r '.body // ""' <<<"$release")
  for marker in \
    "one_kvm_version=$ONE_KVM_VERSION" \
    "one_kvm_release=$UPSTREAM_TAG" \
    "package_sha256=$PACKAGE_DIGEST" \
    "build_number=$BUILD_NUMBER" \
    "build_revision=$BUILD_REVISION" \
    "build_tag=$BUILD_TAG" \
    "builder_commit=$BUILDER_COMMIT" \
    "image_name=$IMAGE_NAME" \
    "compressed_image_name=$IMAGE_NAME.xz" \
    'checksums_name=SHA256SUMS' \
    'manifest_name=manifest.json' \
    'validation_report_name=validation-report.json' \
    "image_sha256=$(digest "${assets[0]}")" \
    "compressed_image_sha256=$(digest "${assets[1]}")" \
    "checksums_sha256=$(digest "${assets[2]}")" \
    "manifest_sha256=$(digest "${assets[3]}")" \
    "validation_report_sha256=$(digest "${assets[4]}")"; do
    local marker_key marker_count
    marker_key=${marker%%=*}
    marker_count=$(awk -F= -v key="$marker_key" '$1 == key {count++} END {print count + 0}' <<<"$body")
    [[ "$marker_count" -eq 1 ]] && grep -Fqx "$marker" <<<"$body" || {
      echo "remote release body marker missing or duplicated: $marker" >&2
      return 1
    }
  done
  for asset in "${assets[@]}"; do
    local name expected actual state count
    name=${asset##*/}
    expected="sha256:$(digest "$asset")"
    count=$(jq --arg name "$name" '[.assets[] | select(.name == $name)] | length' <<<"$release")
    [[ "$count" -eq 1 ]]
    actual=$(jq -er --arg name "$name" '.assets[] | select(.name == $name) | .digest' <<<"$release")
    state=$(jq -er --arg name "$name" '.assets[] | select(.name == $name) | .state' <<<"$release")
    [[ "$state" == uploaded && "$actual" == "$expected" ]] || {
      echo "remote asset verification failed: $name" >&2
      return 1
    }
  done
}

verify_remote_assets true
gh api --method PATCH "repos/$GITHUB_REPOSITORY/releases/$release_id" \
  -F draft=false -F prerelease=false >/dev/null
verify_remote_assets false
tag_commit=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$BUILD_TAG" | jq -er '.object.sha')
[[ "$tag_commit" == "$BUILDER_COMMIT" ]] || { echo 'published tag changed commit' >&2; exit 1; }

trap - EXIT
rm -f -- "$notes_file"
echo "Published immutable Release $BUILD_TAG"
