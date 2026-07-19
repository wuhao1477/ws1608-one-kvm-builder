#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/config/base.env"
OUTPUT_DIR=${OUTPUT_DIR:?OUTPUT_DIR is required}
IMAGE_NAME=${IMAGE_NAME:?IMAGE_NAME is required}
VALIDATION_REPORT_NAME=${VALIDATION_REPORT_NAME:-validation-report.json}
export BASE_BOARD BASE_ID BASE_KERNEL BASE_IMAGE_SHA256
export OUTPUT_DIR IMAGE_NAME VALIDATION_REPORT_NAME

require_basename() {
  local value=$1
  local label=$2
  if [[ -z "$value" || "$value" == . || "$value" == .. || "$value" == *"/"* || "$value" == *"\\"* ]]; then
    echo "$label is not a basename: $value" >&2
    exit 1
  fi
}

require_basename "$IMAGE_NAME" IMAGE_NAME
require_basename "$VALIDATION_REPORT_NAME" VALIDATION_REPORT_NAME

for command in node xz sha256sum; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done

image="$OUTPUT_DIR/$IMAGE_NAME"
compressed="$image.xz"
test -s "$image"
test -s "$OUTPUT_DIR/$VALIDATION_REPORT_NAME"

xz -T0 -9e -c "$image" > "$compressed"
node "$ROOT_DIR/scripts/finalize-release.mjs" "$OUTPUT_DIR"
"$ROOT_DIR/scripts/verify-release-assets.sh"
