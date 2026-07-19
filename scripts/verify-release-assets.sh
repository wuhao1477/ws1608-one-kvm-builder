#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/config/tool-versions.env"
OUTPUT_DIR=${OUTPUT_DIR:?OUTPUT_DIR is required}
IMAGE_NAME=${IMAGE_NAME:?IMAGE_NAME is required}
VALIDATION_REPORT_NAME=${VALIDATION_REPORT_NAME:-validation-report.json}
ONE_KVM_VERSION=${ONE_KVM_VERSION:?ONE_KVM_VERSION is required}
UPSTREAM_TAG=${UPSTREAM_TAG:?UPSTREAM_TAG is required}
PACKAGE_NAME=${PACKAGE_NAME:?PACKAGE_NAME is required}
PACKAGE_URL=${PACKAGE_URL:?PACKAGE_URL is required}
PACKAGE_DIGEST=${PACKAGE_DIGEST:?PACKAGE_DIGEST is required}
BUILD_TAG=${BUILD_TAG:?BUILD_TAG is required}
BUILD_REVISION=${BUILD_REVISION:?BUILD_REVISION is required}
BUILD_NUMBER=${BUILD_NUMBER:?BUILD_NUMBER is required}
BUILDER_COMMIT=${BUILDER_COMMIT:?BUILDER_COMMIT is required}
GITHUB_RUN_ID=${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}
GITHUB_RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}
GITHUB_RUN_NUMBER=${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER is required}
export BASE_BOARD BASE_ID BASE_KERNEL BASE_RELEASE_TAG BASE_IMAGE_NAME BASE_IMAGE_URL BASE_IMAGE_SHA256
export AMLIMG_REPOSITORY AMLIMG_COMMIT
export ONE_KVM_VERSION UPSTREAM_TAG PACKAGE_NAME PACKAGE_URL PACKAGE_DIGEST BUILD_TAG BUILD_REVISION BUILD_NUMBER BUILDER_COMMIT
export GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_RUN_NUMBER OUTPUT_DIR IMAGE_NAME VALIDATION_REPORT_NAME

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
[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || { echo "invalid OUTPUT_DIR: $OUTPUT_DIR" >&2; exit 1; }

for command in node xz sha256sum awk; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done

image="$OUTPUT_DIR/$IMAGE_NAME"
compressed="$image.xz"
node "$ROOT_DIR/scripts/verify-release-assets.mjs" "$OUTPUT_DIR"
xz -t "$compressed"
raw_sha256=$(sha256sum "$image" | awk '{print $1}')
expanded_sha256=$(xz -dc "$compressed" | sha256sum | awk '{print $1}')
[[ "$raw_sha256" == "$expanded_sha256" ]] || {
  echo 'compressed image does not match raw image' >&2
  exit 1
}
(cd "$OUTPUT_DIR" && sha256sum --check SHA256SUMS)
