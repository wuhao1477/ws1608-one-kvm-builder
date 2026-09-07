#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

"$ROOT_DIR/scripts/build-image.sh"
IMAGE="$OUTPUT_DIR/$IMAGE_NAME" BASE_IMAGE="$WORK_DIR/base.burn.img" \
  VERIFY_DIR="$WORK_DIR/verify" "$ROOT_DIR/scripts/verify-image.sh"
"$ROOT_DIR/scripts/package-release.sh"
"$ROOT_DIR/scripts/verify-release-assets.sh"
