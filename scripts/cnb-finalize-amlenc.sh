#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/scripts/cnb-ci-env.sh"
CONTEXT_FILE=${1:?usage: cnb-finalize-amlenc.sh CONTEXT_FILE DOWNLOAD_DIR}
OUTPUT_DIR=${2:?usage: cnb-finalize-amlenc.sh CONTEXT_FILE DOWNLOAD_DIR}
source "$CONTEXT_FILE"
[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || { echo 'invalid downloaded AMLENC artifact directory' >&2; exit 1; }

"$ROOT_DIR/experimental/amlenc/scripts/verify-burn-release.sh" "$OUTPUT_DIR"
BASE_IMAGE="$BASE_IMAGE" \
  IMAGE="$OUTPUT_DIR/$IMAGE_NAME" \
  MANIFEST="$OUTPUT_DIR/manifest.json" \
  AMLIMG_BIN="$AMLIMG_BIN" \
  VERIFY_DIR="$WORK_DIR/download-verify" \
  "$ROOT_DIR/experimental/amlenc/scripts/verify-burn-image.sh"

if [[ "$PUBLISH" == true && "$ACKNOWLEDGE_EXPERIMENTAL" == true ]]; then
  release_tag="ws1608-amlenc-exp-0.2.6-v260802-k3.10.107-b$(printf '%06d' "$((GITHUB_RUN_NUMBER * 1000 + GITHUB_RUN_ATTEMPT))")"
  notes="$ROOT_DIR/.build/amlenc/release-notes.md"
  cat >"$notes" <<EOF
Experimental WS1608/S805 image with One-KVM Rust 0.2.6 and the Meson8b AMLENC H.264 integration.

Hosted build and image validation passed. Physical flashing, boot, and hardware encoding were not tested for this build.
EOF
  RELEASE_TAG="$release_tag" RELEASE_NAME="WS1608 AMLENC experimental $BUILD_NUMBER" \
    RELEASE_COMMIT="$CNB_COMMIT" RELEASE_NOTES_FILE="$notes" \
    RELEASE_ASSET_DIR="$OUTPUT_DIR" RELEASE_PRERELEASE=true \
    RELEASE_LATEST=false "$ROOT_DIR/scripts/cnb-publish-release.sh"
fi
