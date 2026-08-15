#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
OUTPUT_DIR=${AMLENC_DIAGNOSTIC_IMAGE_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/diagnostic-image}
WORK_DIR=${AMLENC_DIAGNOSTIC_VERIFY_WORK_DIR:-$ROOT_DIR/.build/amlenc/diagnostic-verify}
MANIFEST="$OUTPUT_DIR/manifest.json"
SOURCE_LOCKS="$ROOT_DIR/experimental/amlenc/config/sources.env"
# shellcheck disable=SC1090
source "$SOURCE_LOCKS"
IMAGE_NAME=$(jq -er '.image_name' "$MANIFEST")
IMAGE="$OUTPUT_DIR/$IMAGE_NAME"
ROOTFS_UUID=$(jq -er '.rootfs_uuid' "$MANIFEST")

[[ -f "$IMAGE" && ! -L "$IMAGE" && -f "$OUTPUT_DIR/SHA256SUMS" ]] || exit 1
(cd "$OUTPUT_DIR" && sha256sum --check --strict SHA256SUMS)
jq -e --arg bullseye "$BULLSEYE_ARMV7_OCI_IMAGE" --arg tools "$IMAGE_TOOLS_ARM64_OCI_IMAGE" '
  .kind == "ws1608-amlenc-diagnostic-usb-image" and
  .hardware_encoder_tested == false and .one_kvm_included == false and
  .stable_channel_modified == false and .bullseye_oci_image == $bullseye and
  .image_tools_oci_image == $tools
' "$MANIFEST" >/dev/null

mkdir -p "$WORK_DIR"
find "$WORK_DIR" -mindepth 1 -delete
dd if="$IMAGE" of="$WORK_DIR/boot.fat" bs=1048576 skip=16 count=256 status=none
dd if="$IMAGE" of="$WORK_DIR/rootfs.ext4" bs=1048576 skip=272 count=1336 status=none

docker run --rm --platform linux/arm64 \
  -v "$WORK_DIR:/work" -v "$OUTPUT_DIR:/output:ro" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/apt-install.sh:/usr/local/bin/apt-install:ro" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/verify-debugfs-mode.sh:/usr/local/bin/verify-debugfs-mode:ro" \
  "$IMAGE_TOOLS_ARM64_OCI_IMAGE" sh -euxc '
    apt-install e2fsprogs dosfstools fdisk mtools u-boot-tools file binutils jq >/dev/null
    sfdisk --verify /output/'"$IMAGE_NAME"'
    sfdisk --json /output/'"$IMAGE_NAME"' >/work/partitions.json
    jq -e ".partitiontable.label == \"dos\" and
      .partitiontable.partitions[0].start == 32768 and
      .partitiontable.partitions[0].size == 524288 and
      .partitiontable.partitions[0].type == \"6\" and
      .partitiontable.partitions[1].start == 557056 and
      .partitiontable.partitions[1].size == 2736128 and
      .partitiontable.partitions[1].type == \"83\"" /work/partitions.json >/dev/null
    fsck.vfat -vn /work/boot.fat
    e2fsck -fn /work/rootfs.ext4
    test "$(blkid -s UUID -o value /work/rootfs.ext4)" = '"$ROOTFS_UUID"'
    mkdir -p /work/boot-files
    mcopy -s -i /work/boot.fat ::uImage ::boot.scr ::boot.cmd ::amlencEnv.txt ::ws1608-s805.dtb /work/boot-files/
    mkimage -l /work/boot-files/uImage | grep -q Linux-3.10.107-WS1608-AMLENC
    mkimage -l /work/boot-files/boot.scr | grep -q WS1608-AMLENC-USB
    grep -Fqx "bootm 0x20800000 - 0x21800000" /work/boot-files/boot.cmd
    grep -Fqx "rootdev=UUID='"$ROOTFS_UUID"'" /work/boot-files/amlencEnv.txt
    debugfs -R "stat /usr/local/libexec/ws1608-amlenc/amlenc-m8-diag" /work/rootfs.ext4 2>/dev/null | verify-debugfs-mode 0755
    debugfs -R "stat /usr/local/lib/ws1608-amlenc/libvpcodec.so" /work/rootfs.ext4 2>/dev/null | verify-debugfs-mode 0644
    debugfs -R "stat /sbin/init" /work/rootfs.ext4 2>/dev/null | verify-debugfs-mode 0755
    debugfs -R "stat /lib/modules/3.10.107" /work/rootfs.ext4 2>/dev/null | grep -q "Type: directory"
    debugfs -R "cat /etc/ssh/sshd_config.d/ws1608-amlenc.conf" /work/rootfs.ext4 2>/dev/null | grep -Fqx "PasswordAuthentication no"
    debugfs -R "cat /etc/ws1608-amlenc-release.json" /work/rootfs.ext4 2>/dev/null | jq -e ".hardware_encoder_tested == false" >/dev/null
    debugfs -R "cat /etc/shadow" /work/rootfs.ext4 2>/dev/null | grep -Eq "^root:[!*]"
    for package in libc6 openssh-server ffmpeg sysvinit-core; do
      debugfs -R "cat /usr/share/ws1608-amlenc-packages.txt" /work/rootfs.ext4 2>/dev/null \
        | grep -Eq "^${package} [^ ]+ armhf$"
    done
    for file_path in /sbin/init /usr/local/libexec/ws1608-amlenc/amlenc-m8-diag /usr/local/lib/ws1608-amlenc/libvpcodec.so; do
      target=/work/$(basename "$file_path")
      debugfs -R "dump $file_path $target" /work/rootfs.ext4 >/dev/null 2>&1
      file "$target" | grep -Eq "ELF 32-bit LSB.*ARM.*EABI5.*dynamically linked"
    done
    if debugfs -R "stat /usr/bin/one-kvm" /work/rootfs.ext4 2>/dev/null | grep -q "Type: regular"; then
      debugfs -R "stat /etc/init.d/one-kvm" /work/rootfs.ext4 2>/dev/null | verify-debugfs-mode 0755
      debugfs -R "stat /etc/rc2.d/S99one-kvm" /work/rootfs.ext4 2>/dev/null | grep -q "Type: symlink"
      debugfs -R "dump /usr/bin/one-kvm /work/one-kvm" /work/rootfs.ext4 >/dev/null 2>&1
      file /work/one-kvm | grep -Eq "ELF 32-bit LSB.*ARM.*EABI5.*dynamically linked"
    fi
  '
docker run --rm --platform linux/arm/v7 -v "$WORK_DIR:/work:ro" \
  "$BULLSEYE_ARMV7_OCI_IMAGE" sh -euxc \
  'cp /work/amlenc-m8-diag /work/libvpcodec.so /tmp/
   chmod 0755 /tmp/amlenc-m8-diag
   LD_LIBRARY_PATH=/tmp /tmp/amlenc-m8-diag --abi-check /tmp/libvpcodec.so'
file "$IMAGE" | grep -Eq 'DOS/MBR boot sector|partition'
echo "verified WS1608 AMLENC diagnostic USB image"
