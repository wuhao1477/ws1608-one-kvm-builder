#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/config/base.env"
UPSTREAM_REPOSITORY=${UPSTREAM_REPOSITORY:-mofeng-git/One-KVM}
FORCE_BUILD=${FORCE_BUILD:-false}
BASE_FLAVOR=${BASE_FLAVOR:?BASE_FLAVOR is required}
TMP_DIR=$(mktemp -d)
trap 'find "$TMP_DIR" -depth -delete' EXIT

curl --fail --silent --show-error --location --retry 5 \
  "https://api.github.com/repos/$UPSTREAM_REPOSITORY/releases/latest" >"$TMP_DIR/upstream.json"
cnb releases list-releases --repo "$CNB_REPO_SLUG" --page-size 100 --verbose \
  | jq '[.data[]? | .assets = [(.assets // [])[] | {name, state: "uploaded", digest: (if .hash_value then "sha256:" + .hash_value else null end)}]]' \
  >"$TMP_DIR/releases.json"
cnb git list-tags --repo "$CNB_REPO_SLUG" --page-size 100 --verbose \
  | jq '[.data[]? | {name: .name}]' >"$TMP_DIR/tags.json"

node "$ROOT_DIR/scripts/discover-release.mjs" \
  "$TMP_DIR/upstream.json" "$TMP_DIR/releases.json" "$TMP_DIR/tags.json" \
  "$FORCE_BUILD" '' '' "$BASE_FLAVOR"
