#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPSTREAM_REPOSITORY=${UPSTREAM_REPOSITORY:-mofeng-git/One-KVM}
TARGET_REPOSITORY=${GITHUB_REPOSITORY:-}
FORCE_BUILD=${FORCE_BUILD:-false}
OUTPUT_FILE=${GITHUB_OUTPUT:-/dev/null}
WORKFLOW_RUN_NUMBER=${GITHUB_RUN_NUMBER:-}
WORKFLOW_RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:-}

for command in gh node; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done

release_file=$(mktemp)
releases_file=$(mktemp)
tags_file=$(mktemp)
cleanup() { rm -f "$release_file" "$releases_file" "$tags_file"; }
trap cleanup EXIT

gh api "repos/$UPSTREAM_REPOSITORY/releases/latest" > "$release_file"
if [[ -n "$TARGET_REPOSITORY" ]]; then
  gh api --paginate --slurp "repos/$TARGET_REPOSITORY/releases?per_page=100" > "$releases_file"
  gh api --paginate --slurp "repos/$TARGET_REPOSITORY/tags?per_page=100" > "$tags_file"
else
  printf '[]\n' > "$releases_file"
  printf '[]\n' > "$tags_file"
fi

node "$ROOT_DIR/scripts/discover-release.mjs" \
  "$release_file" "$releases_file" "$tags_file" "$FORCE_BUILD" \
  "$WORKFLOW_RUN_NUMBER" "$WORKFLOW_RUN_ATTEMPT" >> "$OUTPUT_FILE"
