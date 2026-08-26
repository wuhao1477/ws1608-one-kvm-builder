#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/experimental/amlenc/config/sources.env"
source "$ROOT_DIR/experimental/amlenc/config/legacy-bringup.env"

BASE_IMAGE_XZ=${BASE_IMAGE_XZ:?BASE_IMAGE_XZ is required}
LEGACY_KERNEL_DIR=${LEGACY_KERNEL_DIR:?LEGACY_KERNEL_DIR is required}
ENCODER_DIR=${ENCODER_DIR:?ENCODER_DIR is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:?SSH_PUBLIC_KEY is required}
BUILD_REVISION=${BUILD_REVISION:?BUILD_REVISION is required}
OUTPUT_DIR=${OUTPUT_DIR:-$ROOT_DIR/out/amlenc/legacy-bringup}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/.build/amlenc/legacy-bringup}
IMAGE_NAME="WS1608-AMLENC-Bringup_${BUILD_REVISION}_Onecloud_bullseye_3.10.107-recovery6.12.28.burn.img"

fail() { echo "legacy bring-up image failed: $*" >&2; exit 1; }
require_file() { [[ -f "$1" && ! -L "$1" && -s "$1" ]] || fail "invalid file: $1"; }
basename_only() { [[ -n "$1" && "$1" != */* && "$1" != *'\\'* && "$1" != . && "$1" != .. ]] || fail "unsafe package entry"; }
for command in awk jq mcopy mkimage node sha1sum sha256sum xz; do command -v "$command" >/dev/null || fail "missing command: $command"; done
require_file "$BASE_IMAGE_XZ"
for file in zImage ws1608-s805.dtb modules.tar.gz source-manifest.json; do require_file "$LEGACY_KERNEL_DIR/$file"; done
for file in libvpcodec.so amlenc-m8-diag source-manifest.json SHA256SUMS; do require_file "$ENCODER_DIR/$file"; done
[[ -x "$AMLIMG_BIN" ]] || fail "AmlImg is not executable"
[[ "$BUILD_REVISION" =~ ^b[0-9]{6}$ ]] || fail "invalid build revision"
[[ "$SSH_PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || fail "invalid SSH public key"
[[ "$WORK_DIR" != / && "$WORK_DIR" != "$ROOT_DIR" && ! -L "$WORK_DIR" ]] || fail "unsafe work directory"
[[ "$OUTPUT_DIR" != / && "$OUTPUT_DIR" != "$ROOT_DIR" && ! -L "$OUTPUT_DIR" ]] || fail "unsafe output directory"

BASE_IMAGE="$WORK_DIR/base.burn.img"
PACKAGE_DIR="$WORK_DIR/package"
BASE_BOOT_RAW="$WORK_DIR/base-boot.raw"
BASE_ROOTFS_RAW="$WORK_DIR/base-rootfs.raw"
FINAL_BOOT_RAW="$WORK_DIR/final-boot.raw"
FINAL_ROOTFS_RAW="$WORK_DIR/final-rootfs.raw"
BOOT_FILES="$WORK_DIR/boot-files"
MANIFEST="$OUTPUT_DIR/manifest.json"

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
find "$WORK_DIR" -mindepth 1 -delete
find "$OUTPUT_DIR" -mindepth 1 -delete
xz -dc "$BASE_IMAGE_XZ" >"$BASE_IMAGE"
mkdir -p "$PACKAGE_DIR" "$BOOT_FILES/dtb"
"$AMLIMG_BIN" unpack "$BASE_IMAGE" "$PACKAGE_DIR"
boot_sparse=$(awk -F: '$1=="PARTITION"&&$2=="boot"{print $4;exit}' "$PACKAGE_DIR/commands.txt")
rootfs_sparse=$(awk -F: '$1=="PARTITION"&&$2=="rootfs"{print $4;exit}' "$PACKAGE_DIR/commands.txt")
boot_verify=$(awk -F: '$1=="VERIFY"&&$2=="boot"{print $4;exit}' "$PACKAGE_DIR/commands.txt")
rootfs_verify=$(awk -F: '$1=="VERIFY"&&$2=="rootfs"{print $4;exit}' "$PACKAGE_DIR/commands.txt")
for value in "$boot_sparse" "$rootfs_sparse" "$boot_verify" "$rootfs_verify"; do basename_only "$value"; done
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$PACKAGE_DIR/$boot_sparse" "$BASE_BOOT_RAW"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$PACKAGE_DIR/$rootfs_sparse" "$BASE_ROOTFS_RAW"
cp "$BASE_BOOT_RAW" "$FINAL_BOOT_RAW"

RECOVERY_ROOTFS_RAW="$BASE_ROOTFS_RAW" LEGACY_MODULES_TAR="$LEGACY_KERNEL_DIR/modules.tar.gz" \
  ENCODER_DIR="$ENCODER_DIR" \
  SSH_PUBLIC_KEY="$SSH_PUBLIC_KEY" OUTPUT_ROOTFS_RAW="$FINAL_ROOTFS_RAW" \
  WORK_DIR="$WORK_DIR/rootfs-work" "$ROOT_DIR/experimental/amlenc/scripts/build-legacy-rootfs.sh"
LEGACY_INITRD="$WORK_DIR/rootfs-work/amlenc-initrd"
require_file "$LEGACY_INITRD"

mcopy -i "$BASE_BOOT_RAW" ::uImage "$BOOT_FILES/uImage.recovery"
mcopy -i "$BASE_BOOT_RAW" ::uInitrd "$BOOT_FILES/uInitrd.recovery"
mcopy -i "$BASE_BOOT_RAW" ::dtb/meson8b-onecloud.dtb "$BOOT_FILES/dtb/meson8b-onecloud.recovery.dtb"
mkimage -A arm -O linux -T kernel -C none -a 0x00208000 -e 0x00208000 \
  -n Linux-3.10.107-WS1608-AMLENC -d "$LEGACY_KERNEL_DIR/zImage" "$BOOT_FILES/uImage.amlenc"
mkimage -A arm -O linux -T ramdisk -C none \
  -n Linux-3.10.107-AMLENC-initrd -d "$LEGACY_INITRD" "$BOOT_FILES/uInitrd.amlenc"
cp "$LEGACY_KERNEL_DIR/ws1608-s805.dtb" "$BOOT_FILES/dtb/meson8b-onecloud-amlenc.dtb"
node "$ROOT_DIR/experimental/amlenc/scripts/render-legacy-trial-boot.mjs" \
  "$BOOT_FILES" "$LEGACY_ROOTFS_UUID" "$BUILD_REVISION"
mkimage -A arm -O linux -T script -C none -n WS1608-AMLENC-Bringup \
  -d "$BOOT_FILES/boot.cmd" "$BOOT_FILES/boot.scr"
for file in uImage.recovery uInitrd.recovery uImage.amlenc uInitrd.amlenc boot.cmd boot.scr armbianEnv.txt amlenc-force-recovery; do
  mcopy -o -i "$FINAL_BOOT_RAW" "$BOOT_FILES/$file" "::$file"
done
mcopy -o -i "$FINAL_BOOT_RAW" "$BOOT_FILES/dtb/meson8b-onecloud.recovery.dtb" ::dtb/meson8b-onecloud.recovery.dtb
mcopy -o -i "$FINAL_BOOT_RAW" "$BOOT_FILES/dtb/meson8b-onecloud-amlenc.dtb" ::dtb/meson8b-onecloud-amlenc.dtb

node "$ROOT_DIR/scripts/raw-to-sparse.mjs" "$FINAL_BOOT_RAW" "$PACKAGE_DIR/$boot_sparse"
node "$ROOT_DIR/scripts/raw-to-sparse.mjs" "$FINAL_ROOTFS_RAW" "$PACKAGE_DIR/$rootfs_sparse"
printf 'sha1sum %s' "$(sha1sum "$PACKAGE_DIR/$boot_sparse" | awk '{print $1}')" >"$PACKAGE_DIR/$boot_verify"
printf 'sha1sum %s' "$(sha1sum "$PACKAGE_DIR/$rootfs_sparse" | awk '{print $1}')" >"$PACKAGE_DIR/$rootfs_verify"
"$AMLIMG_BIN" pack "$OUTPUT_DIR/$IMAGE_NAME" "$PACKAGE_DIR"

image_sha256=$(sha256sum "$OUTPUT_DIR/$IMAGE_NAME" | awk '{print $1}')
key_sha256=$(printf '%s\n' "$SSH_PUBLIC_KEY" | sha256sum | awk '{print $1}')
boot_sha256=$(sha256sum "$PACKAGE_DIR/$boot_sparse" | awk '{print $1}')
rootfs_sha256=$(sha256sum "$PACKAGE_DIR/$rootfs_sparse" | awk '{print $1}')
encoder_commit=$(jq -er '.commit' "$ENCODER_DIR/source-manifest.json")
encoder_abi=$(jq -er '.abi' "$ENCODER_DIR/source-manifest.json")
encoder_redistribution=$(jq -er '.redistribution' "$ENCODER_DIR/source-manifest.json")
encoder_sha256=$(sha256sum "$ENCODER_DIR/libvpcodec.so" | awk '{print $1}')
diagnostic_sha256=$(sha256sum "$ENCODER_DIR/amlenc-m8-diag" | awk '{print $1}')
initrd_sha256=$(sha256sum "$BOOT_FILES/uInitrd.amlenc" | awk '{print $1}')
jq -n --arg image "$IMAGE_NAME" --arg image_sha "$image_sha256" --arg revision "$BUILD_REVISION" \
  --arg base_tag "$BASE_RELEASE_TAG" --arg base_sha "$BASE_IMAGE_SHA256" --arg key_sha "$key_sha256" \
  --arg boot_sha "$boot_sha256" --arg rootfs_sha "$rootfs_sha256" --arg linux "$LINUX_COMMIT" \
  --arg encoder_commit "$encoder_commit" --arg encoder_sha "$encoder_sha256" \
  --arg diagnostic_sha "$diagnostic_sha256" --arg initrd_sha "$initrd_sha256" \
  --argjson encoder_abi "$encoder_abi" \
  --arg encoder_redistribution "$encoder_redistribution" \
  '{schema:1,kind:"ws1608-amlenc-legacy-bringup",image_name:$image,image_sha256:$image_sha,
    build_revision:$revision,base_release_tag:$base_tag,base_image_sha256:$base_sha,
    recovery:{kernel:"6.12.28-current-meson",source:"stable-base"},
    legacy:{kernel:"3.10.107",commit:$linux,cma_mib:64,initrd_sha256:$initrd_sha},
    diagnostic_included:true,
    encoder:{commit:$encoder_commit,abi:$encoder_abi,redistribution:$encoder_redistribution,
      libvpcodec_sha256:$encoder_sha,diagnostic_sha256:$diagnostic_sha},
    partitions:{boot_sha256:$boot_sha,rootfs_sha256:$rootfs_sha},ssh_public_key_sha256:$key_sha,
    default_login_user:"root",password_authentication:true,
    recovery_first:true,hardware_boot_tested:false,hardware_encoder_tested:false,
    one_kvm_included:false,hid_tested:false,msd_tested:false,stable_channel_modified:false}' >"$MANIFEST"
echo "built $OUTPUT_DIR/$IMAGE_NAME"
