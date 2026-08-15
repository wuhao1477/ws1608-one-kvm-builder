#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/config/tool-versions.env"

BASE_IMAGE_XZ=${BASE_IMAGE_XZ:?BASE_IMAGE_XZ is required}
DIAGNOSTIC_IMAGE=${DIAGNOSTIC_IMAGE:?DIAGNOSTIC_IMAGE is required}
DIAGNOSTIC_MANIFEST=${DIAGNOSTIC_MANIFEST:?DIAGNOSTIC_MANIFEST is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
OUTPUT_DIR=${OUTPUT_DIR:-$ROOT_DIR/out/amlenc/burn}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/.build/amlenc/burn}
BUILD_REVISION=${BUILD_REVISION:-local001}
IMAGE_NAME=${IMAGE_NAME:-WS1608-AMLENC_0.2.6+ws1608amlenc.${BUILD_REVISION}_Onecloud_bullseye_3.10.107.burn.img}

BASE_IMAGE="$WORK_DIR/base.burn.img"
PACKAGE_DIR="$WORK_DIR/package"
BOOT_RAW="$WORK_DIR/boot.raw"
ROOTFS_RAW="$WORK_DIR/rootfs.raw"
DIAG_MANIFEST="$WORK_DIR/diagnostic-manifest.json"
MANIFEST="$OUTPUT_DIR/manifest.json"

fail() { echo "burn image build failed: $*" >&2; exit 1; }
require_file() { [[ -f "$1" && ! -L "$1" && -s "$1" ]] || fail "missing file: $1"; }
require_basename() { [[ "$1" != /* && "$1" != *'/'* && "$1" != *'\\'* && "$1" != . && "$1" != .. ]] || fail "unsafe basename: $2"; }
need_command() { command -v "$1" >/dev/null || fail "missing command: $1"; }
read_command_file() { awk -F: -v type="$1" -v name="$2" '$1 == type && $2 == name {print $4; exit}' "$PACKAGE_DIR/commands.txt"; }

for command in awk dd jq node sha1sum sha256sum stat xz; do need_command "$command"; done
require_file "$BASE_IMAGE_XZ"
require_file "$DIAGNOSTIC_IMAGE"
[[ -x "$AMLIMG_BIN" ]] || fail "AmlImg is not executable"
[[ "$BUILD_REVISION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ ]] || fail "unsafe build revision"
require_basename "$IMAGE_NAME" IMAGE_NAME
mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
[[ ! -L "$OUTPUT_DIR" && ! -L "$WORK_DIR" ]] || fail "build directories must not be symlinks"
rm -rf "$PACKAGE_DIR"
rm -f "$BASE_IMAGE" "$BOOT_RAW" "$ROOTFS_RAW" "$MANIFEST" "$OUTPUT_DIR/$IMAGE_NAME"

xz -dc "$BASE_IMAGE_XZ" >"$BASE_IMAGE"
mkdir -p "$PACKAGE_DIR"
"$AMLIMG_BIN" unpack "$BASE_IMAGE" "$PACKAGE_DIR"
boot_sparse=$(read_command_file PARTITION boot)
rootfs_sparse=$(read_command_file PARTITION rootfs)
boot_verify=$(read_command_file VERIFY boot)
rootfs_verify=$(read_command_file VERIFY rootfs)
for value in "$boot_sparse" "$rootfs_sparse" "$boot_verify" "$rootfs_verify"; do require_basename "$value" package_entry; done

cp "$DIAGNOSTIC_MANIFEST" "$DIAG_MANIFEST"
jq -e '.kind == "ws1608-amlenc-diagnostic-usb-image" and .one_kvm_included == true and .hardware_encoder_tested == false and .stable_channel_modified == false' "$DIAG_MANIFEST" >/dev/null || fail "diagnostic image is not an integrated untested candidate"

dd if="$DIAGNOSTIC_IMAGE" of="$BOOT_RAW" bs=1048576 skip=16 count=256 status=none
dd if="$DIAGNOSTIC_IMAGE" of="$ROOTFS_RAW" bs=1048576 skip=272 count=1336 status=none
[[ $(stat -c '%s' "$BOOT_RAW") == 268435456 ]] || fail "unexpected boot partition size"
[[ $(stat -c '%s' "$ROOTFS_RAW") == 1400897536 ]] || fail "unexpected rootfs partition size"
node "$ROOT_DIR/scripts/raw-to-sparse.mjs" "$BOOT_RAW" "$PACKAGE_DIR/$boot_sparse"
node "$ROOT_DIR/scripts/raw-to-sparse.mjs" "$ROOTFS_RAW" "$PACKAGE_DIR/$rootfs_sparse"
printf 'sha1sum %s' "$(sha1sum "$PACKAGE_DIR/$boot_sparse" | awk '{print $1}')" >"$PACKAGE_DIR/$boot_verify"
printf 'sha1sum %s' "$(sha1sum "$PACKAGE_DIR/$rootfs_sparse" | awk '{print $1}')" >"$PACKAGE_DIR/$rootfs_verify"

"$AMLIMG_BIN" pack "$OUTPUT_DIR/$IMAGE_NAME" "$PACKAGE_DIR"
image_sha256=$(sha256sum "$OUTPUT_DIR/$IMAGE_NAME" | awk '{print $1}')
jq -n \
  --arg kind ws1608-amlenc-burn-image --arg image_name "$IMAGE_NAME" \
  --arg image_sha256 "$image_sha256" --arg revision "$BUILD_REVISION" \
  --arg base_tag "$BASE_RELEASE_TAG" --arg base_name "$BASE_IMAGE_NAME" \
  --arg one_kvm_version "$(jq -er '.one_kvm.version' "$DIAG_MANIFEST")" \
  --arg one_kvm_sha256 "$(jq -er '.one_kvm.sha256' "$DIAG_MANIFEST")" \
  --arg kernel_commit "$(jq -er '.kernel.commit' "$DIAG_MANIFEST")" \
  --arg kernel_version "$(jq -er '.kernel.version' "$DIAG_MANIFEST")" \
  --arg encoder_commit "$(jq -er '.encoder.commit' "$DIAG_MANIFEST")" \
  '{schema: 1, kind: $kind, image_name: $image_name, image_sha256: $image_sha256,
    build_revision: $revision, base_release_tag: $base_tag, base_image_name: $base_name,
    kernel: {version: $kernel_version, commit: $kernel_commit},
    encoder: {commit: $encoder_commit, codec: "h264_amlenc"},
    one_kvm: {version: $one_kvm_version, sha256: $one_kvm_sha256},
    hardware_encoder_tested: false, hardware_boot_tested: false,
    one_kvm_included: true, stable_channel_modified: false}' >"$MANIFEST"
printf 'built %s\n' "$OUTPUT_DIR/$IMAGE_NAME"
