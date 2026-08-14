#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=${1:?usage: prepare-public-artifact.sh SOURCE_DIR DESTINATION_DIR}
DESTINATION_DIR=${2:?usage: prepare-public-artifact.sh SOURCE_DIR DESTINATION_DIR}
[[ -d "$SOURCE_DIR" ]] || { echo "source directory is missing: $SOURCE_DIR" >&2; exit 1; }
[[ "$DESTINATION_DIR" != / && "$DESTINATION_DIR" != . && "$DESTINATION_DIR" != "$SOURCE_DIR" ]]
for command in find jq cp mkdir; do command -v "$command" >/dev/null || exit 1; done

encoder_manifest="$SOURCE_DIR/libvpcodec/source-manifest.json"
[[ -f "$encoder_manifest" && ! -L "$encoder_manifest" ]] || {
  echo "encoder source manifest is missing or unsafe" >&2
  exit 1
}
jq -e '.redistribution == "local-test-only"' "$encoder_manifest" >/dev/null || {
  echo "expected local-test-only redistribution" >&2
  exit 1
}

if [[ -e "$DESTINATION_DIR" ]]; then
  [[ -d "$DESTINATION_DIR" && -z "$(find "$DESTINATION_DIR" -mindepth 1 -print -quit)" ]] || {
    echo "destination directory must be empty" >&2
    exit 1
  }
else
  mkdir -p "$DESTINATION_DIR"
fi

count=0
while IFS= read -r -d '' source; do
  [[ ! -L "$source" ]] || { echo "refusing symbolic link: $source" >&2; exit 1; }
  relative=${source#"$SOURCE_DIR"/}
  destination="$DESTINATION_DIR/$relative"
  mkdir -p "$(dirname "$destination")"
  cp "$source" "$destination"
  count=$((count + 1))
done < <(find "$SOURCE_DIR" -type f \( \
  -name '*.json' -o -name '*.sha256' -o -name 'SHA256SUMS' -o -name '*.txt' \
  \) -print0)

((count > 0)) || { echo "no public metadata files found" >&2; exit 1; }
echo "prepared $count public metadata files"
