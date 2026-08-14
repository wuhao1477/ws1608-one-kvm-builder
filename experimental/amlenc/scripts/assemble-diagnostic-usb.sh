#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SOURCE_LOCKS="$ROOT_DIR/experimental/amlenc/config/sources.env"
KERNEL_DIR=${AMLENC_KERNEL_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/kernel}
ENCODER_DIR=${AMLENC_LIBVPCODEC_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/libvpcodec}
OUTPUT_DIR=${AMLENC_DIAGNOSTIC_IMAGE_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/diagnostic-image}
WORK_DIR=${AMLENC_DIAGNOSTIC_IMAGE_WORK_DIR:-$ROOT_DIR/.build/amlenc/diagnostic-image}
BUILD_REVISION=${AMLENC_BUILD_REVISION:-local001}
PUBLIC_KEY=${AMLENC_SSH_PUBLIC_KEY:-}
ROOTFS_UUID=7c59bb76-d17e-4a9c-9ff8-031b35133010
ROOTFS_BYTES=1400897536
BOOT_BYTES=268435456
BOOT_START=16777216
ROOTFS_START=285212672

# shellcheck disable=SC1090
source "$SOURCE_LOCKS"
IMAGE_NAME="WS1608-AMLENC-Diagnostic_k3.10.107_bullseye_${BUILD_REVISION}.usb.img"
IMAGE_PATH="$OUTPUT_DIR/$IMAGE_NAME"
ROOTFS_TAR="$WORK_DIR/rootfs.tar"
ROOTFS_IMAGE="$WORK_DIR/rootfs.ext4"
BOOT_IMAGE="$WORK_DIR/boot.fat"
BOOT_FILES="$WORK_DIR/boot-files"

[[ "$PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || {
  echo "AMLENC_SSH_PUBLIC_KEY must contain one OpenSSH public key" >&2
  exit 1
}
for command in docker jq sha256sum truncate; do command -v "$command" >/dev/null; done
[[ ! -L "$WORK_DIR" && "$WORK_DIR" != / && "$WORK_DIR" != "$ROOT_DIR" ]] || exit 1
mkdir -p "$WORK_DIR"
find "$WORK_DIR" -mindepth 1 -delete
mkdir -p "$BOOT_FILES"

docker run --rm --platform linux/arm/v7 \
  -v "$WORK_DIR:/work" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/apt-install.sh:/build-tools/apt-install:ro" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/write-package-manifest.sh:/build-tools/write-package-manifest:ro" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/archive-rootfs.sh:/build-tools/archive-rootfs:ro" \
  "$BULLSEYE_ARMV7_OCI_IMAGE" sh -euxc '
    export DEBIAN_FRONTEND=noninteractive
    /build-tools/apt-install sysvinit-core initscripts udev kmod \
      ifupdown isc-dhcp-client openssh-server ca-certificates ffmpeg jq iproute2 procps
    passwd -l root
    rm -f /etc/ssh/ssh_host_* /etc/machine-id
    : >/etc/machine-id
    find /var/lib/apt/lists /var/cache/apt/archives /tmp /var/tmp -mindepth 1 -delete
    /build-tools/write-package-manifest /usr/share/ws1608-amlenc-packages.txt
    /build-tools/archive-rootfs /work/rootfs.tar /
  '

cp "$KERNEL_DIR/zImage" "$BOOT_FILES/zImage"
cp "$KERNEL_DIR/ws1608-s805.dtb" "$BOOT_FILES/ws1608-s805.dtb"
node "$ROOT_DIR/experimental/amlenc/scripts/render-diagnostic-boot.mjs" "$BOOT_FILES" "$ROOTFS_UUID"

docker run --rm --platform linux/arm64 \
  -e AMLENC_SSH_PUBLIC_KEY="$PUBLIC_KEY" \
  -v "$WORK_DIR:/work" -v "$KERNEL_DIR:/kernel:ro" -v "$ENCODER_DIR:/encoder:ro" \
  -v "$OUTPUT_DIR:/output:ro" -v "$ROOT_DIR/experimental/amlenc:/repo:ro" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/apt-install.sh:/usr/local/bin/apt-install:ro" \
  "$IMAGE_TOOLS_ARM64_OCI_IMAGE" sh -euxc '
    apt-install e2fsprogs dosfstools fdisk mtools u-boot-tools >/dev/null
    mkdir /rootfs-tree
    tar --numeric-owner --xattrs --acls -xpf /work/rootfs.tar -C /rootfs-tree
    ln -s /proc/mounts /rootfs-tree/etc/mtab
    tar -xzf /kernel/modules.tar.gz -C /rootfs-tree
    /repo/scripts/install-file.sh 0755 /encoder/amlenc-m8-diag \
      /rootfs-tree/usr/local/libexec/ws1608-amlenc/amlenc-m8-diag
    /repo/scripts/install-file.sh 0755 /repo/scripts/validate-h264.sh \
      /rootfs-tree/usr/local/libexec/ws1608-amlenc/validate-h264.sh
    /repo/scripts/install-file.sh 0644 /encoder/libvpcodec.so \
      /rootfs-tree/usr/local/lib/ws1608-amlenc/libvpcodec.so
    /repo/scripts/install-file.sh 0644 /repo/config/hardware-limits.json \
      /rootfs-tree/usr/local/share/ws1608-amlenc/hardware-limits.json
    /repo/scripts/install-file.sh 0644 /output/input-manifest.json \
      /rootfs-tree/etc/ws1608-amlenc-release.json
    /repo/scripts/configure-diagnostic-rootfs.sh /rootfs-tree
    printf "proc /proc proc defaults 0 0\nsysfs /sys sysfs defaults 0 0\ntmpfs /run tmpfs mode=0755,nosuid,nodev 0 0\n" \
      >/rootfs-tree/etc/fstab
    truncate -s '"$ROOTFS_BYTES"' /work/rootfs.ext4
    mkfs.ext4 -F -L amlenc_root -U '"$ROOTFS_UUID"' \
      -O ^64bit,^metadata_csum,^orphan_file -d /rootfs-tree /work/rootfs.ext4
    e2fsck -fy /work/rootfs.ext4
    truncate -s '"$BOOT_BYTES"' /work/boot.fat
    mkfs.vfat -F 16 -n AMLENC_BOOT /work/boot.fat
    mkimage -A arm -O linux -T kernel -C none -a 0x00208000 -e 0x00208000 \
      -n Linux-3.10.107-WS1608-AMLENC -d /work/boot-files/zImage /work/boot-files/uImage
    mkimage -A arm -O linux -T script -C none \
      -n WS1608-AMLENC-USB -d /work/boot-files/boot.cmd /work/boot-files/boot.scr
    mcopy -i /work/boot.fat /work/boot-files/uImage ::uImage
    mcopy -i /work/boot.fat /work/boot-files/ws1608-s805.dtb ::ws1608-s805.dtb
    mcopy -i /work/boot.fat /work/boot-files/boot.scr ::boot.scr
    mcopy -i /work/boot.fat /work/boot-files/boot.cmd ::boot.cmd
    mcopy -i /work/boot.fat /work/boot-files/amlencEnv.txt ::amlencEnv.txt
  '

truncate -s "$((ROOTFS_START + ROOTFS_BYTES))" "$IMAGE_PATH"
docker run --rm --platform linux/arm64 \
  -v "$OUTPUT_DIR:/output" -v "$WORK_DIR:/work" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/apt-install.sh:/usr/local/bin/apt-install:ro" \
  "$IMAGE_TOOLS_ARM64_OCI_IMAGE" sh -euxc '
    apt-install fdisk >/dev/null
    printf "label: dos\nunit: sectors\n\nstart=32768,size=524288,type=6,bootable\nstart=557056,size=2736128,type=83\n" \
      | sfdisk /output/'"$IMAGE_NAME"'
  '
dd if="$BOOT_IMAGE" of="$IMAGE_PATH" bs=1048576 seek="$((BOOT_START / 1048576))" conv=notrunc status=none
dd if="$ROOTFS_IMAGE" of="$IMAGE_PATH" bs=1048576 seek="$((ROOTFS_START / 1048576))" conv=notrunc status=none

public_key_sha256=$(printf '%s\n' "$PUBLIC_KEY" | sha256sum | awk '{print $1}')
jq --arg image "$IMAGE_NAME" --arg uuid "$ROOTFS_UUID" --arg key "$public_key_sha256" \
  --arg bullseye "$BULLSEYE_ARMV7_OCI_IMAGE" --arg tools "$IMAGE_TOOLS_ARM64_OCI_IMAGE" \
  '. + {image_name:$image, rootfs_uuid:$uuid, ssh_public_key_sha256:$key,
    bullseye_oci_image:$bullseye, image_tools_oci_image:$tools}' \
  "$OUTPUT_DIR/input-manifest.json" >"$OUTPUT_DIR/manifest.json"
sha256sum "$IMAGE_PATH" "$OUTPUT_DIR/manifest.json" | sed "s#$OUTPUT_DIR/##" >"$OUTPUT_DIR/SHA256SUMS"
echo "built $IMAGE_PATH"
