#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/config/base.env"
OUTPUT_DIR=${OUTPUT_DIR:?OUTPUT_DIR is required}
IMAGE_NAME=${IMAGE_NAME:?IMAGE_NAME is required}
VALIDATION_REPORT_NAME=${VALIDATION_REPORT_NAME:-validation-report.json}
export BASE_BOARD BASE_ID BASE_KERNEL BASE_IMAGE_SHA256
export OUTPUT_DIR IMAGE_NAME VALIDATION_REPORT_NAME

for command in node xz sha256sum awk; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done

image="$OUTPUT_DIR/$IMAGE_NAME"
compressed="$image.xz"
xz -t "$compressed"
raw_sha256=$(sha256sum "$image" | awk '{print $1}')
expanded_sha256=$(xz -dc "$compressed" | sha256sum | awk '{print $1}')
[[ "$raw_sha256" == "$expanded_sha256" ]] || {
  echo 'compressed image does not match raw image' >&2
  exit 1
}
(cd "$OUTPUT_DIR" && sha256sum --check SHA256SUMS)
node "$ROOT_DIR/scripts/verify-release-assets.mjs" "$OUTPUT_DIR"
