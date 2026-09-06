#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/scripts/cnb-ci-env.sh"
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/config/tool-versions.env"

FORCE_BUILD=${FORCE_BUILD:-false}
PUBLISH=${PUBLISH:-true}
RELEASE_PRERELEASE=${RELEASE_PRERELEASE:-false}
discovery=$(mktemp)
trap 'rm -f "$discovery"' EXIT
FORCE_BUILD="$FORCE_BUILD" "$ROOT_DIR/scripts/cnb-discover-release.sh" >"$discovery"
source "$discovery"
[[ "$changed" == true ]] || { echo "no new One-KVM input for $release_tag"; exit 0; }

export BASE_ID BASE_FLAVOR BASE_KERNEL BASE_BOARD BASE_RELEASE_TAG
export BASE_IMAGE_NAME BASE_IMAGE_URL BASE_IMAGE_SHA256 AMLIMG_REPOSITORY AMLIMG_COMMIT
export ONE_KVM_VERSION UPSTREAM_TAG PACKAGE_NAME PACKAGE_URL PACKAGE_DIGEST
export BUILD_TAG BUILD_NUMBER BUILD_REVISION BUILDER_COMMIT
export GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_RUN_NUMBER
export OUTPUT_DIR="$ROOT_DIR/out/cnb-stable/$BUILD_TAG"
export WORK_DIR="$ROOT_DIR/.build/cnb-stable/$BUILD_TAG"
export VALIDATION_REPORT="$OUTPUT_DIR/validation-report.json"
export VALIDATION_REPORT_NAME=validation-report.json
export IMAGE_NAME="One-KVM_${IMAGE_STEM}_${BASE_FLAVOR}.burn.img"
export GITHUB_OUTPUT=/dev/null

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
export TOOLS_DIR="$WORK_DIR/tools"
export AMLIMG_BIN
AMLIMG_BIN=$(TOOLS_DIR="$TOOLS_DIR" "$ROOT_DIR/scripts/build-tools.sh")

curl --fail --silent --show-error --location --retry 5 "$BASE_IMAGE_URL" \
  -o "$WORK_DIR/$BASE_IMAGE_NAME"
printf '%s  %s\n' "$BASE_IMAGE_SHA256" "$WORK_DIR/$BASE_IMAGE_NAME" | sha256sum --check
export BASE_IMAGE_XZ="$WORK_DIR/$BASE_IMAGE_NAME"
curl --fail --silent --show-error --location --retry 5 "$PACKAGE_URL" \
  -o "$WORK_DIR/$PACKAGE_NAME"
printf '%s  %s\n' "$PACKAGE_DIGEST" "$WORK_DIR/$PACKAGE_NAME" | sha256sum --check
dpkg-deb -f "$WORK_DIR/$PACKAGE_NAME" Package | grep -Fx one-kvm >/dev/null
dpkg-deb -f "$WORK_DIR/$PACKAGE_NAME" Version | grep -Fx "$ONE_KVM_VERSION" >/dev/null
dpkg-deb -f "$WORK_DIR/$PACKAGE_NAME" Architecture | grep -Fx armhf >/dev/null
export ONE_KVM_DEB="$WORK_DIR/$PACKAGE_NAME"

"$ROOT_DIR/scripts/build-image.sh"
IMAGE="$OUTPUT_DIR/$IMAGE_NAME" BASE_IMAGE="$WORK_DIR/base.burn.img" \
  VERIFY_DIR="$WORK_DIR/verify" "$ROOT_DIR/scripts/verify-image.sh"
"$ROOT_DIR/scripts/package-release.sh"
"$ROOT_DIR/scripts/verify-release-assets.sh"

cat >"$WORK_DIR/release-notes.md" <<EOF
## WS1608 One-KVM Rust $ONE_KVM_VERSION

Upstream One-KVM release: [$UPSTREAM_TAG](https://github.com/mofeng-git/One-KVM/releases/tag/$UPSTREAM_TAG)

Build: $BUILD_REVISION. Base: Armbian $BASE_RELEASE_TAG, kernel $BASE_KERNEL, $BASE_FLAVOR.

Built and published by CNB. Hosted validation cannot flash a physical WS1608; this is not a hardware boot result.
EOF

if [[ "$PUBLISH" == true ]]; then
  RELEASE_TAG="$BUILD_TAG" RELEASE_NAME="WS1608 One-KVM Rust $ONE_KVM_VERSION ($UPSTREAM_TAG, $BUILD_REVISION)" \
    RELEASE_COMMIT="$BUILDER_COMMIT" RELEASE_NOTES_FILE="$WORK_DIR/release-notes.md" \
    RELEASE_ASSET_DIR="$OUTPUT_DIR" RELEASE_PRERELEASE="$RELEASE_PRERELEASE" \
    RELEASE_LATEST="$([[ "$RELEASE_PRERELEASE" == false ]] && printf true || printf false)" \
    "$ROOT_DIR/scripts/cnb-publish-release.sh"
else
  CNB_ASSET_TTL=14 "$ROOT_DIR/scripts/cnb-upload-commit-assets.sh" "$OUTPUT_DIR"
fi
