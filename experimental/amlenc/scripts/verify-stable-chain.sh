#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/../../..}" && pwd)
MANIFEST=${2:-$ROOT_DIR/experimental/amlenc/config/stable-chain.sha256}
[[ -f "$MANIFEST" ]] || { echo "stable-chain manifest is missing: $MANIFEST" >&2; exit 1; }
for command in git shasum awk sort cmp mktemp; do command -v "$command" >/dev/null || exit 1; done

expected=$(mktemp)
actual=$(mktemp)
check_output=$(mktemp)
trap 'rm -f "$expected" "$actual" "$check_output"' EXIT

git -C "$ROOT_DIR" ls-files -- \
  .github/workflows/build.yml config package.json scripts tests \
  | LC_ALL=C sort >"$expected"

awk '
  length($1) != 64 || $1 !~ /^[0-9a-f]+$/ || NF != 2 || $2 ~ /^\// || $2 ~ /(^|\/)\.\.($|\/)/ { exit 1 }
  { print $2 }
' "$MANIFEST" | LC_ALL=C sort >"$actual"

if ! cmp -s "$expected" "$actual"; then
  echo "stable-chain path set does not match tracked protected files" >&2
  exit 1
fi

if ! (cd "$ROOT_DIR" && shasum -a 256 -c "$MANIFEST") >"$check_output" 2>&1; then
  cat "$check_output" >&2
  exit 1
fi

count=$(awk 'END { print NR }' "$actual")
echo "verified $count stable-chain files"
