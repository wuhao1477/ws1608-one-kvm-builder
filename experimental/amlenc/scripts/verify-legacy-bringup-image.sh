#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/experimental/amlenc/config/sources.env"

IMAGE=${IMAGE:?IMAGE is required}
MANIFEST=${MANIFEST:?MANIFEST is required}
BASE_IMAGE=${BASE_IMAGE:?BASE_IMAGE is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
VERIFY_DIR=${VERIFY_DIR:-$ROOT_DIR/.build/amlenc/legacy-bringup-verify}

fail() { echo "legacy bring-up verification failed: $*" >&2; exit 1; }
basename_only() { [[ -n "$1" && "$1" != */* && "$1" != *'\\'* && "$1" != . && "$1" != .. ]] || fail "unsafe package entry"; }
for command in awk cmp cut debugfs dumpe2fs e2fsck file grep jq mcopy mkimage node realpath sha1sum sha256sum; do
  command -v "$command" >/dev/null || fail "missing command: $command"
done
for artifact in "$IMAGE" "$MANIFEST" "$BASE_IMAGE"; do [[ -f "$artifact" && ! -L "$artifact" ]] || fail "invalid artifact"; done
[[ -x "$AMLIMG_BIN" ]] || fail "AmlImg is not executable"
resolved=$(realpath -m -- "$VERIFY_DIR")
[[ "$resolved" != / && "$resolved" != "$ROOT_DIR" && ! -L "$VERIFY_DIR" ]] || fail "unsafe verify directory"

mkdir -p "$VERIFY_DIR"
find "$VERIFY_DIR" -mindepth 1 -delete
FINAL_DIR="$VERIFY_DIR/final"
BASE_DIR="$VERIFY_DIR/base"
mkdir -p "$FINAL_DIR" "$BASE_DIR"
"$AMLIMG_BIN" unpack "$IMAGE" "$FINAL_DIR"
"$AMLIMG_BIN" unpack "$BASE_IMAGE" "$BASE_DIR"
cmp "$BASE_DIR/commands.txt" "$FINAL_DIR/commands.txt" || fail "commands.txt changed"

declare -A final_partition base_partition verify_file
while IFS=: read -r type name image_type filename; do
  basename_only "$filename"
  if [[ "$name" != boot && "$name" != rootfs ]]; then
    cmp "$BASE_DIR/$filename" "$FINAL_DIR/$filename" || fail "$type $name changed"
  fi
  if [[ "$type" == PARTITION ]]; then
    final_partition[$name]="$FINAL_DIR/$filename"
    base_partition[$name]="$BASE_DIR/$filename"
  elif [[ "$type" == VERIFY ]]; then
    verify_file[$name]="$FINAL_DIR/$filename"
  fi
done <"$FINAL_DIR/commands.txt"

for name in boot rootfs bootloader resource; do
  [[ -f "${final_partition[$name]:-}" && -f "${verify_file[$name]:-}" ]] || fail "missing $name partition"
  expected=$(<"${verify_file[$name]}")
  actual="sha1sum $(sha1sum "${final_partition[$name]}" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || fail "$name VERIFY mismatch"
done
cmp --silent "${base_partition[boot]}" "${final_partition[boot]}" && fail "boot partition was not changed"
cmp --silent "${base_partition[rootfs]}" "${final_partition[rootfs]}" && fail "rootfs partition was not changed"

BOOT_RAW="$VERIFY_DIR/boot.raw"
BASE_BOOT_RAW="$VERIFY_DIR/base-boot.raw"
ROOTFS_RAW="$VERIFY_DIR/rootfs.raw"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "${final_partition[boot]}" "$BOOT_RAW"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "${base_partition[boot]}" "$BASE_BOOT_RAW"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "${final_partition[rootfs]}" "$ROOTFS_RAW"
e2fsck -fn "$ROOTFS_RAW" >/dev/null || fail "rootfs filesystem check"
features=$(dumpe2fs -h "$ROOTFS_RAW" 2>/dev/null | awk -F: '/Filesystem features/{print $2}')
for feature in 64bit metadata_csum orphan_file; do [[ " $features " != *" $feature "* ]] || fail "unsupported ext4 feature $feature"; done

BOOT_FILES="$VERIFY_DIR/boot-files"
BASE_BOOT_FILES="$VERIFY_DIR/base-boot-files"
mkdir -p "$BOOT_FILES" "$BASE_BOOT_FILES"
mcopy -i "$BASE_BOOT_RAW" ::uImage "$BASE_BOOT_FILES/uImage"
mcopy -i "$BASE_BOOT_RAW" ::uInitrd "$BASE_BOOT_FILES/uInitrd"
mcopy -i "$BASE_BOOT_RAW" ::dtb/meson8b-onecloud.dtb "$BASE_BOOT_FILES/meson8b-onecloud.dtb"
for file in uImage.recovery uInitrd.recovery uImage.amlenc boot.cmd boot.scr armbianEnv.txt amlenc-force-recovery; do
  mcopy -i "$BOOT_RAW" "::$file" "$BOOT_FILES/$file"
done
mcopy -i "$BOOT_RAW" ::dtb/meson8b-onecloud.recovery.dtb "$BOOT_FILES/meson8b-onecloud.recovery.dtb"
mcopy -i "$BOOT_RAW" ::dtb/meson8b-onecloud-amlenc.dtb "$BOOT_FILES/meson8b-onecloud-amlenc.dtb"
cmp "$BASE_BOOT_FILES/uImage" "$BOOT_FILES/uImage.recovery" || fail "recovery uImage changed"
cmp "$BASE_BOOT_FILES/uInitrd" "$BOOT_FILES/uInitrd.recovery" || fail "recovery uInitrd changed"
cmp "$BASE_BOOT_FILES/meson8b-onecloud.dtb" "$BOOT_FILES/meson8b-onecloud.recovery.dtb" || fail "recovery DTB changed"
mkimage -l "$BOOT_FILES/uImage.amlenc" | grep -q 'Linux-3.10.107-WS1608-AMLENC' || fail "legacy uImage identity"
mkimage -l "$BOOT_FILES/boot.scr" | grep -q 'WS1608-AMLENC-Bringup' || fail "boot script identity"
[[ "$(<"$BOOT_FILES/amlenc-force-recovery")" == recovery-first ]] || fail "force-recovery marker"
force_line=$(grep -n -m1 amlenc-force-recovery "$BOOT_FILES/boot.cmd" | cut -d: -f1)
success_line=$(grep -n -m1 amlenc-3.10.ok "$BOOT_FILES/boot.cmd" | cut -d: -f1)
trial_line=$(grep -n -m1 amlenc_trial_revision "$BOOT_FILES/boot.cmd" | cut -d: -f1)
[[ "$force_line" -lt "$success_line" && "$success_line" -lt "$trial_line" ]] || fail "boot branch order"

for path in \
  /lib/modules/6.12.28-current-meson \
  /lib/modules/3.10.107 \
  /usr/local/sbin/ws1608-amlenc-arm-trial \
  /usr/local/sbin/ws1608-amlenc-mark-success; do
  debugfs -R "stat $path" "$ROOTFS_RAW" 2>/dev/null | grep -q 'Inode:' || fail "missing rootfs path $path"
done
for helper in ws1608-amlenc-arm-trial ws1608-amlenc-mark-success; do
  debugfs -R "stat /usr/local/sbin/$helper" "$ROOTFS_RAW" 2>/dev/null | grep -q 'Mode:  0755' || fail "$helper mode"
done
ssh_config=$(debugfs -R 'cat /etc/ssh/sshd_config.d/ws1608-amlenc.conf' "$ROOTFS_RAW" 2>/dev/null)
grep -Fqx 'PasswordAuthentication no' <<<"$ssh_config" || fail "SSH password policy"
grep -Fqx 'PubkeyAuthentication yes' <<<"$ssh_config" || fail "SSH public-key policy"
fstab=$(debugfs -R 'cat /etc/fstab' "$ROOTFS_RAW" 2>/dev/null)
grep -Fq 'LABEL=armbi_boot /boot vfat' <<<"$fstab" || fail "boot mount policy"
if debugfs -R 'stat /usr/bin/one-kvm' "$ROOTFS_RAW" 2>/dev/null | grep -q 'Inode:'; then fail "one-kvm must not be installed"; fi

jq -e --arg base_tag "$BASE_RELEASE_TAG" --arg base_sha "$BASE_IMAGE_SHA256" --arg linux "$LINUX_COMMIT" '
  .schema == 1 and .kind == "ws1608-amlenc-legacy-bringup" and
  .base_release_tag == $base_tag and .base_image_sha256 == $base_sha and
  .recovery == {kernel:"6.12.28-current-meson",source:"stable-base"} and
  .legacy == {kernel:"3.10.107",commit:$linux,cma_mib:64} and .recovery_first == true and
  .hardware_boot_tested == false and .hardware_encoder_tested == false and
  .one_kvm_included == false and .hid_tested == false and .msd_tested == false and
  .stable_channel_modified == false
' "$MANIFEST" >/dev/null || fail "manifest gate"
[[ "$(sha256sum "$IMAGE" | awk '{print $1}')" == "$(jq -er '.image_sha256' "$MANIFEST")" ]] || fail "image digest"
[[ "$(sha256sum "${final_partition[boot]}" | awk '{print $1}')" == "$(jq -er '.partitions.boot_sha256' "$MANIFEST")" ]] || fail "boot digest"
[[ "$(sha256sum "${final_partition[rootfs]}" | awk '{print $1}')" == "$(jq -er '.partitions.rootfs_sha256' "$MANIFEST")" ]] || fail "rootfs digest"
echo "verified WS1608 recovery-first legacy bring-up image"
