#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/experimental/amlenc/config/sources.env"

BASE_IMAGE_XZ=${BASE_IMAGE_XZ:?BASE_IMAGE_XZ is required}
ONE_KVM_DEB=${ONE_KVM_DEB:?ONE_KVM_DEB is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
BUILD_NUMBER=${BUILD_NUMBER:?BUILD_NUMBER is required}
BUILD_REVISION=${BUILD_REVISION:?BUILD_REVISION is required}
EXPERIMENTAL_BUILD_TAG=${EXPERIMENTAL_BUILD_TAG:?EXPERIMENTAL_BUILD_TAG is required}
BUILDER_COMMIT=${BUILDER_COMMIT:?BUILDER_COMMIT is required}
IMAGE_NAME=${IMAGE_NAME:?IMAGE_NAME is required}
GITHUB_RUN_ID=${GITHUB_RUN_ID:-local}
GITHUB_RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:-1}
GITHUB_RUN_NUMBER=${GITHUB_RUN_NUMBER:-$BUILD_NUMBER}
OUTPUT_DIR=${OUTPUT_DIR:-$ROOT_DIR/out/amlenc/burn}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/.build/amlenc/burn}

STAGING_DIR="$WORK_DIR/staging"
INJECTION_DIR="$WORK_DIR/stable-rootfs"
PACKAGE_DIR="$WORK_DIR/final-package"
MANIFEST="$OUTPUT_DIR/manifest.json"

fail() { echo "burn image build failed: $*" >&2; exit 1; }
require_file() { [[ -f "$1" && ! -L "$1" && -s "$1" ]] || fail "missing file: $1"; }
require_basename() { [[ -n "$1" && "$1" != /* && "$1" != *'/'* && "$1" != *'\\'* && "$1" != . && "$1" != .. ]] || fail "unsafe basename: $2"; }
need_command() { command -v "$1" >/dev/null || fail "missing command: $1"; }
require_private_dir() {
  local resolved
  resolved=$(realpath -m -- "$1")
  [[ "$resolved" != / && "$resolved" != "$ROOT_DIR" && ! -L "$1" ]] || fail "unsafe build directory: $2"
}

for command in awk dpkg-deb jq node realpath sha256sum; do need_command "$command"; done
require_file "$BASE_IMAGE_XZ"
require_file "$ONE_KVM_DEB"
[[ -x "$AMLIMG_BIN" ]] || fail "AmlImg is not executable"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail "BUILD_NUMBER must be a positive integer"
expected_revision=$(printf 'b%06d' "$BUILD_NUMBER")
[[ "$BUILD_REVISION" == "$expected_revision" ]] || fail "BUILD_REVISION must equal $expected_revision"
expected_tag="ws1608-amlenc-exp-${ONE_KVM_VERSION}-${ONE_KVM_REF}-k6.12.28-$BUILD_REVISION"
[[ "$EXPERIMENTAL_BUILD_TAG" == "$expected_tag" ]] || fail "EXPERIMENTAL_BUILD_TAG must equal $expected_tag"
require_basename "$IMAGE_NAME" IMAGE_NAME
require_private_dir "$OUTPUT_DIR" OUTPUT_DIR
require_private_dir "$WORK_DIR" WORK_DIR

package_name=$(dpkg-deb -f "$ONE_KVM_DEB" Package)
package_version=$(dpkg-deb -f "$ONE_KVM_DEB" Version)
package_arch=$(dpkg-deb -f "$ONE_KVM_DEB" Architecture)
package_file=${ONE_KVM_DEB##*/}
package_sha256=$(sha256sum "$ONE_KVM_DEB" | awk '{print $1}')
[[ "$package_name" == one-kvm ]] || fail "unexpected package: $package_name"
[[ "$package_arch" == armhf ]] || fail "unexpected package architecture: $package_arch"
package_prefix="${ONE_KVM_VERSION}+ws1608amlenc."
[[ "$package_version" == "$package_prefix"* ]] || fail "unexpected package version: $package_version"
package_build=${package_version#"$package_prefix"}
[[ "$package_build" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,31}$ ]] || fail "unsafe package build identity: $package_build"
[[ "$IMAGE_NAME" == *"${package_version}"* && "$IMAGE_NAME" == *'_Onecloud_trixie_6.12.28.burn.img' ]] || fail "image name must identify the One-KVM and stable kernel versions"

internal_tag="ws1608-one-kvm-$EXPERIMENTAL_BUILD_TAG"
internal_name="One-KVM_${EXPERIMENTAL_BUILD_TAG}_${BASE_FLAVOR}.burn.img"

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
[[ ! -L "$OUTPUT_DIR" && ! -L "$WORK_DIR" ]] || fail "build directories must not be symlinks"
rm -rf "$STAGING_DIR" "$PACKAGE_DIR"
rm -f "$OUTPUT_DIR/$IMAGE_NAME" "$MANIFEST"
mkdir -p "$STAGING_DIR"

# The verified stable builder changes rootfs only and byte-compares its boot console.
env \
  BASE_IMAGE_XZ="$BASE_IMAGE_XZ" ONE_KVM_DEB="$ONE_KVM_DEB" AMLIMG_BIN="$AMLIMG_BIN" \
  ONE_KVM_VERSION="$package_version" UPSTREAM_TAG="$ONE_KVM_REF" \
  PACKAGE_NAME="$package_file" PACKAGE_URL="github-actions://$GITHUB_RUN_ID/$package_file" \
  PACKAGE_DIGEST="$package_sha256" BUILD_TAG="$internal_tag" BUILD_NUMBER="$BUILD_NUMBER" \
  BUILD_REVISION="$BUILD_REVISION" BUILDER_COMMIT="$BUILDER_COMMIT" IMAGE_NAME="$internal_name" \
  GITHUB_RUN_ID="$GITHUB_RUN_ID" GITHUB_RUN_ATTEMPT="$GITHUB_RUN_ATTEMPT" \
  GITHUB_RUN_NUMBER="$GITHUB_RUN_NUMBER" OUTPUT_DIR="$STAGING_DIR" WORK_DIR="$INJECTION_DIR" \
  "$ROOT_DIR/scripts/build-image.sh"

mv "$STAGING_DIR/$internal_name" "$OUTPUT_DIR/$IMAGE_NAME"
mkdir -p "$PACKAGE_DIR"
"$AMLIMG_BIN" unpack "$OUTPUT_DIR/$IMAGE_NAME" "$PACKAGE_DIR"
boot_sparse=$(awk -F: '$1 == "PARTITION" && $2 == "boot" {print $4; exit}' "$PACKAGE_DIR/commands.txt")
require_basename "$boot_sparse" boot_partition
boot_sha256=$(sha256sum "$PACKAGE_DIR/$boot_sparse" | awk '{print $1}')
image_sha256=$(sha256sum "$OUTPUT_DIR/$IMAGE_NAME" | awk '{print $1}')

jq -n \
  --arg kind ws1608-amlenc-burn-image --arg image_name "$IMAGE_NAME" \
  --arg image_sha256 "$image_sha256" --arg revision "$BUILD_REVISION" \
  --arg build_tag "$EXPERIMENTAL_BUILD_TAG" \
  --arg base_tag "$BASE_RELEASE_TAG" --arg base_name "$BASE_IMAGE_NAME" \
  --arg base_url "$BASE_IMAGE_URL" --arg base_sha256 "$BASE_IMAGE_SHA256" \
  --arg base_kernel "$BASE_KERNEL" --arg boot_sha256 "$boot_sha256" \
  --arg one_kvm_version "$package_version" --arg one_kvm_sha256 "$package_sha256" \
  --arg one_kvm_ref "$ONE_KVM_REF" --arg one_kvm_commit "$ONE_KVM_COMMIT" \
  --arg encoder_commit "$AMLENC_COMMIT" \
  '{schema: 1, kind: $kind, image_name: $image_name, image_sha256: $image_sha256,
    build_revision: $revision, build_tag: $build_tag, stable_base_preserved: true,
    base_release_tag: $base_tag, base_image_name: $base_name,
    base_image_url: $base_url, base_image_sha256: $base_sha256,
    boot_partition_sha256: $boot_sha256,
    kernel: {version: $base_kernel, source: "stable-base"},
    encoder: {commit: $encoder_commit, codec: "h264_amlenc", driver_status: "research-only"},
    one_kvm: {version: $one_kvm_version, sha256: $one_kvm_sha256,
      upstream_ref: $one_kvm_ref, upstream_commit: $one_kvm_commit},
    hardware_encoder_tested: false, hardware_boot_tested: false,
    one_kvm_included: true, stable_channel_modified: false}' >"$MANIFEST"

rm -rf "$STAGING_DIR" "$PACKAGE_DIR"
printf 'built %s\n' "$OUTPUT_DIR/$IMAGE_NAME"
