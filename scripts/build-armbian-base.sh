#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/config/armbian-build.env"

ARMBIAN_DIR=${ARMBIAN_DIR:?ARMBIAN_DIR is required}
UBOOT_IMAGE=${UBOOT_IMAGE:?UBOOT_IMAGE is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
OUTPUT_DIR=${OUTPUT_DIR:-$ROOT_DIR/out}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/.armbian-build}
OUTPUT_IMAGE="$OUTPUT_DIR/OneCloud_Armbian_${ARMBIAN_RELEASE}_${ARMBIAN_BRANCH}_${ARMBIAN_KERNEL}.burn.img"
PACKAGE_DIR="$WORK_DIR/burn"
UBOOT_DIR="$WORK_DIR/uboot"
VERIFY_DIR="$WORK_DIR/verify"

as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

require_command() {
  command -v "$1" >/dev/null || { echo "missing command: $1" >&2; exit 1; }
}

require_private_dir() {
  local value=$1 label=$2 resolved
  resolved=$(realpath -m -- "$value")
  [[ "$resolved" != / && "$resolved" != "$ROOT_DIR" && ! -L "$value" ]] || {
    echo "$label is not an isolated build directory: $value" >&2
    exit 1
  }
}

for command in cmp diff find git losetup node sha1sum sha256sum; do
  require_command "$command"
done
[[ -x "$AMLIMG_BIN" ]] || { echo "AmlImg binary is not executable: $AMLIMG_BIN" >&2; exit 1; }
[[ -f "$UBOOT_IMAGE" && ! -L "$UBOOT_IMAGE" ]] || { echo "invalid U-Boot image: $UBOOT_IMAGE" >&2; exit 1; }
[[ -d "$ARMBIAN_DIR" && ! -L "$ARMBIAN_DIR" ]] || { echo "invalid Armbian source: $ARMBIAN_DIR" >&2; exit 1; }
require_private_dir "$WORK_DIR" WORK_DIR
require_private_dir "$OUTPUT_DIR" OUTPUT_DIR
[[ "$(git -C "$ARMBIAN_DIR" rev-parse HEAD)" == "$ARMBIAN_COMMIT" ]] || {
  echo 'Armbian source commit does not match the pinned commit' >&2
  exit 1
}

check_sha256() {
  local expected=$1 file=$2
  echo "$expected  $file" | sha256sum --check --quiet
}

check_sha256 "$ARMBIAN_BOARD_SHA256" "$ARMBIAN_DIR/config/boards/onecloud.csc"
check_sha256 "$ARMBIAN_BOOTENV_SHA256" "$ARMBIAN_DIR/config/bootenv/onecloud.txt"
check_sha256 "$ARMBIAN_BOOT_SCRIPT_SHA256" "$ARMBIAN_DIR/config/bootscripts/boot-onecloud.cmd"
check_sha256 "$ARMBIAN_DTS_PATCH_SHA256" "$ARMBIAN_DIR/patch/kernel/archive/meson-6.12/onecloud-0001-add-dts.patch"
check_sha256 "$ARMBIAN_HDMI_DTS_PATCH_SHA256" "$ARMBIAN_DIR/patch/kernel/archive/meson-6.12/onecloud-0002-dts-Support-HDMI.patch"
check_sha256 "$ARMBIAN_HDMI_PATCH_SHA256" "$ARMBIAN_DIR/patch/kernel/archive/meson-6.12/0052-drm-meson-Describe-the-HDMI-PHY-frequency-limits-of-.patch"
check_sha256 "$UBOOT_SHA256" "$UBOOT_IMAGE"

mkdir -p "$OUTPUT_DIR" "$WORK_DIR" "$VERIFY_DIR"
rm -rf -- "$PACKAGE_DIR" "$UBOOT_DIR" "$VERIFY_DIR/unpacked" "$WORK_DIR/disk.img" "$WORK_DIR/loop"
mkdir -p "$PACKAGE_DIR" "$UBOOT_DIR" "$VERIFY_DIR/unpacked"

as_root "$ARMBIAN_DIR/compile.sh" requirements
as_root chown -R "$(id -u):$(id -g)" "$ARMBIAN_DIR"
(
  cd "$ARMBIAN_DIR"
  ./compile.sh build \
    BOARD="$ARMBIAN_BOARD" \
    BRANCH="$ARMBIAN_BRANCH" \
    RELEASE="$ARMBIAN_RELEASE" \
    KERNEL_CONFIGURE=no \
    BUILD_DESKTOP=no \
    BUILD_MINIMAL=no \
    EXPERT=yes \
    COMPRESS_OUTPUTIMAGE=img
)

disk_image=$(find "$ARMBIAN_DIR/output/images" -maxdepth 1 -type f -name '*.img' -print -quit)
[[ -n "$disk_image" ]] || { echo 'Armbian did not produce a raw image' >&2; exit 1; }
cp "$disk_image" "$WORK_DIR/disk.img"
loop_device=$(as_root losetup --find --show --partscan "$WORK_DIR/disk.img")
cleanup_loop() {
  as_root losetup --detach "$loop_device" >/dev/null 2>&1 || true
}
trap cleanup_loop EXIT
for partition in "${loop_device}p1" "${loop_device}p2"; do
  [[ -b "$partition" ]] || { echo "missing Armbian partition: $partition" >&2; exit 1; }
done
as_root node "$ROOT_DIR/scripts/raw-to-sparse.mjs" "${loop_device}p1" "$PACKAGE_DIR/boot.simg"
as_root node "$ROOT_DIR/scripts/raw-to-sparse.mjs" "${loop_device}p2" "$PACKAGE_DIR/rootfs.simg"
as_root chown -R "$(id -u):$(id -g)" "$PACKAGE_DIR"
cleanup_loop
trap - EXIT

"$AMLIMG_BIN" unpack "$UBOOT_IMAGE" "$UBOOT_DIR"
head -n 8 "$ROOT_DIR/config/armbian-burn-commands.expected" |
  diff -u - "$UBOOT_DIR/commands.txt"
cp "$UBOOT_DIR"/* "$PACKAGE_DIR/"
cat >> "$PACKAGE_DIR/commands.txt" <<'EOF'
PARTITION:boot:sparse:boot.simg
VERIFY:boot:normal:boot.VERIFY
PARTITION:rootfs:sparse:rootfs.simg
VERIFY:rootfs:normal:rootfs.VERIFY
EOF
printf 'sha1sum %s' "$(sha1sum "$PACKAGE_DIR/boot.simg" | awk '{print $1}')" > "$PACKAGE_DIR/boot.VERIFY"
printf 'sha1sum %s' "$(sha1sum "$PACKAGE_DIR/rootfs.simg" | awk '{print $1}')" > "$PACKAGE_DIR/rootfs.VERIFY"
rm -f "$OUTPUT_IMAGE"
"$AMLIMG_BIN" pack "$OUTPUT_IMAGE" "$PACKAGE_DIR"
"$AMLIMG_BIN" unpack "$OUTPUT_IMAGE" "$VERIFY_DIR/unpacked"
diff -u "$ROOT_DIR/config/armbian-burn-commands.expected" "$VERIFY_DIR/unpacked/commands.txt"
index=1
while IFS=: read -r type name image_type source_file; do
  final_file=$(sed -n "${index}p" "$VERIFY_DIR/unpacked/commands.txt" | awk -F: '{print $4}')
  cmp "$UBOOT_DIR/$source_file" "$VERIFY_DIR/unpacked/$final_file"
  index=$((index + 1))
done
boot_partition=$(awk -F: '$1 == "PARTITION" && $2 == "boot" {print $4; exit}' "$VERIFY_DIR/unpacked/commands.txt")
rootfs_partition=$(awk -F: '$1 == "PARTITION" && $2 == "rootfs" {print $4; exit}' "$VERIFY_DIR/unpacked/commands.txt")
boot_verify=$(awk -F: '$1 == "VERIFY" && $2 == "boot" {print $4; exit}' "$VERIFY_DIR/unpacked/commands.txt")
rootfs_verify=$(awk -F: '$1 == "VERIFY" && $2 == "rootfs" {print $4; exit}' "$VERIFY_DIR/unpacked/commands.txt")
printf 'sha1sum %s' "$(sha1sum "$VERIFY_DIR/unpacked/$boot_partition" | awk '{print $1}')" |
  cmp - "$VERIFY_DIR/unpacked/$boot_verify"
printf 'sha1sum %s' "$(sha1sum "$VERIFY_DIR/unpacked/$rootfs_partition" | awk '{print $1}')" |
  cmp - "$VERIFY_DIR/unpacked/$rootfs_verify"
echo "Built $OUTPUT_IMAGE"
