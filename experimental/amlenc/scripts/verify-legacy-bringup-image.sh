#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/experimental/amlenc/config/sources.env"
source "$ROOT_DIR/experimental/amlenc/config/legacy-bringup.env"

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
BUILD_REVISION=$(jq -er '.build_revision' "$MANIFEST") || fail "build revision is missing"
[[ "$BUILD_REVISION" =~ ^b[0-9]{6}$ ]] || fail "invalid build revision"
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

final_boot= final_rootfs= final_bootloader= final_resource=
base_boot= base_rootfs= base_bootloader= base_resource=
verify_boot= verify_rootfs= verify_bootloader= verify_resource=
while IFS=: read -r type name image_type filename; do
  basename_only "$filename"
  if [[ "$name" != boot && "$name" != rootfs ]]; then
    cmp "$BASE_DIR/$filename" "$FINAL_DIR/$filename" || fail "$type $name changed"
  fi
  if [[ "$type" == PARTITION ]]; then
    case "$name" in
      boot) final_boot="$FINAL_DIR/$filename"; base_boot="$BASE_DIR/$filename" ;;
      rootfs) final_rootfs="$FINAL_DIR/$filename"; base_rootfs="$BASE_DIR/$filename" ;;
      bootloader) final_bootloader="$FINAL_DIR/$filename"; base_bootloader="$BASE_DIR/$filename" ;;
      resource) final_resource="$FINAL_DIR/$filename"; base_resource="$BASE_DIR/$filename" ;;
    esac
  elif [[ "$type" == VERIFY ]]; then
    case "$name" in
      boot) verify_boot="$FINAL_DIR/$filename" ;;
      rootfs) verify_rootfs="$FINAL_DIR/$filename" ;;
      bootloader) verify_bootloader="$FINAL_DIR/$filename" ;;
      resource) verify_resource="$FINAL_DIR/$filename" ;;
    esac
  fi
done <"$FINAL_DIR/commands.txt"

for name in boot rootfs bootloader resource; do
  case "$name" in
    boot) partition="$final_boot"; verify="$verify_boot" ;;
    rootfs) partition="$final_rootfs"; verify="$verify_rootfs" ;;
    bootloader) partition="$final_bootloader"; verify="$verify_bootloader" ;;
    resource) partition="$final_resource"; verify="$verify_resource" ;;
  esac
  [[ -f "$partition" && -f "$verify" ]] || fail "missing $name partition"
  expected=$(<"$verify")
  actual="sha1sum $(sha1sum "$partition" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || fail "$name VERIFY mismatch"
done
cmp --silent "$base_boot" "$final_boot" && fail "boot partition was not changed"
cmp --silent "$base_rootfs" "$final_rootfs" && fail "rootfs partition was not changed"

BOOT_RAW="$VERIFY_DIR/boot.raw"
BASE_BOOT_RAW="$VERIFY_DIR/base-boot.raw"
ROOTFS_RAW="$VERIFY_DIR/rootfs.raw"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$final_boot" "$BOOT_RAW"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$base_boot" "$BASE_BOOT_RAW"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$final_rootfs" "$ROOTFS_RAW"
e2fsck -fn "$ROOTFS_RAW" >/dev/null || fail "rootfs filesystem check"
features=$(dumpe2fs -h "$ROOTFS_RAW" 2>/dev/null | awk -F: '/Filesystem features/{print $2}')
for feature in 64bit metadata_csum orphan_file; do [[ " $features " != *" $feature "* ]] || fail "unsupported ext4 feature $feature"; done
block_size=$(dumpe2fs -h "$ROOTFS_RAW" 2>/dev/null | awk -F: '/Block size/{gsub(/[[:space:]]/, "", $2); print $2}')
free_blocks=$(dumpe2fs -h "$ROOTFS_RAW" 2>/dev/null | awk -F: '/Free blocks/{gsub(/[[:space:]]/, "", $2); print $2}')
[[ "$block_size" =~ ^[0-9]+$ && "$free_blocks" =~ ^[0-9]+$ ]] || fail "rootfs block statistics"
((free_blocks * block_size >= 134217728)) || fail "rootfs has less than 128 MiB free"

BOOT_FILES="$VERIFY_DIR/boot-files"
BASE_BOOT_FILES="$VERIFY_DIR/base-boot-files"
mkdir -p "$BOOT_FILES" "$BASE_BOOT_FILES"
mcopy -i "$BASE_BOOT_RAW" ::uImage "$BASE_BOOT_FILES/uImage"
mcopy -i "$BASE_BOOT_RAW" ::uInitrd "$BASE_BOOT_FILES/uInitrd"
mcopy -i "$BASE_BOOT_RAW" ::dtb/meson8b-onecloud.dtb "$BASE_BOOT_FILES/meson8b-onecloud.dtb"
for file in uImage.recovery uInitrd.recovery uImage.amlenc uInitrd.amlenc boot.cmd boot.scr armbianEnv.txt amlenc-force-recovery; do
  mcopy -i "$BOOT_RAW" "::$file" "$BOOT_FILES/$file"
done
mcopy -i "$BOOT_RAW" ::dtb/meson8b-onecloud.recovery.dtb "$BOOT_FILES/meson8b-onecloud.recovery.dtb"
mcopy -i "$BOOT_RAW" ::dtb/meson8b-onecloud-amlenc.dtb "$BOOT_FILES/meson8b-onecloud-amlenc.dtb"
cmp "$BASE_BOOT_FILES/uImage" "$BOOT_FILES/uImage.recovery" || fail "recovery uImage changed"
cmp "$BASE_BOOT_FILES/uInitrd" "$BOOT_FILES/uInitrd.recovery" || fail "recovery uInitrd changed"
cmp "$BASE_BOOT_FILES/meson8b-onecloud.dtb" "$BOOT_FILES/meson8b-onecloud.recovery.dtb" || fail "recovery DTB changed"
mkimage -l "$BOOT_FILES/uImage.amlenc" | grep -q 'Linux-3.10.107-WS1608-AMLENC' || fail "legacy uImage identity"
mkimage -l "$BOOT_FILES/uInitrd.amlenc" | grep -q 'Linux-3.10.107-AMLENC-initrd' || fail "legacy initrd identity"
legacy_initrd_sha256=$(sha256sum "$BOOT_FILES/uInitrd.amlenc" | awk '{print $1}')
mkimage -l "$BOOT_FILES/boot.scr" | grep -q 'WS1608-AMLENC-Bringup' || fail "boot script identity"
[[ "$(<"$BOOT_FILES/amlenc-force-recovery")" == recovery-first ]] || fail "force-recovery marker"
armed_line=$(grep -n -m1 amlenc-legacy-trial-armed "$BOOT_FILES/boot.cmd" | cut -d: -f1)
force_line=$(grep -n -m1 amlenc-force-recovery "$BOOT_FILES/boot.cmd" | cut -d: -f1)
success_line=$(grep -n -m1 amlenc-3.10.ok "$BOOT_FILES/boot.cmd" | cut -d: -f1)
trial_set_line=$(grep -n -m1 -F "setenv amlenc_trial_revision ${BUILD_REVISION}" "$BOOT_FILES/boot.cmd" | cut -d: -f1)
! grep -Eq 'button[[:space:]]+reset' "$BOOT_FILES/boot.cmd" || fail "boot path must not require the reset button"
[[ "$force_line" -lt "$armed_line" && "$armed_line" -lt "$trial_set_line" && "$success_line" -gt "$armed_line" ]] || fail "boot branch order"
[[ -n "$trial_set_line" ]] || fail "armed trial revision missing"
grep -Fq 'saveenv ||' "$BOOT_FILES/boot.cmd" || fail "best-effort saveenv gate missing"
grep -Fq 'saveenv || echo' "$BOOT_FILES/boot.cmd" || fail "saveenv fallback message missing"

for path in \
  /lib/modules/6.12.28-current-meson \
  /lib/modules/3.10.107 \
  /usr/local/sbin/ws1608-amlenc-arm-trial \
  /usr/local/sbin/ws1608-amlenc-mark-success \
  /usr/local/sbin/ws1608-amlenc-probe \
  /usr/local/libexec/ws1608-amlenc/amlenc-m8-diag \
  /usr/local/libexec/ws1608-amlenc/validate-h264.sh \
  /usr/local/lib/ws1608-amlenc/libvpcodec.so \
  /usr/local/share/ws1608-amlenc/hardware-limits.json \
  /usr/local/share/ws1608-amlenc/frame-640x480.nv12 \
  /usr/local/share/ws1608-amlenc/frame-1280x720.nv12 \
  /etc/init.d/ws1608-amlenc-firstboot; do
  debugfs -R "stat $path" "$ROOTFS_RAW" 2>/dev/null | grep -q 'Inode:' || fail "missing rootfs path $path"
done
for helper in ws1608-amlenc-arm-trial ws1608-amlenc-mark-success; do
  debugfs -R "stat /usr/local/sbin/$helper" "$ROOTFS_RAW" 2>/dev/null | grep -q 'Mode:  0755' || fail "$helper mode"
done
for helper in /usr/local/sbin/ws1608-amlenc-probe /usr/local/libexec/ws1608-amlenc/amlenc-m8-diag /usr/local/libexec/ws1608-amlenc/validate-h264.sh; do
  debugfs -R "stat $helper" "$ROOTFS_RAW" 2>/dev/null | grep -q 'Mode:  0755' || fail "$helper mode"
done
debugfs -R 'stat /usr/local/lib/ws1608-amlenc/libvpcodec.so' "$ROOTFS_RAW" 2>/dev/null \
  | grep -q 'Mode:  0644' || fail "libvpcodec mode"
for fixture in frame-640x480.nv12 frame-1280x720.nv12; do
  debugfs -R "stat /usr/local/share/ws1608-amlenc/$fixture" "$ROOTFS_RAW" 2>/dev/null \
    | grep -q 'Mode:  0644' || fail "$fixture mode"
done
debugfs -R 'stat /etc/init.d/ws1608-amlenc-firstboot' "$ROOTFS_RAW" 2>/dev/null \
  | grep -q 'Mode:  0755' || fail "firstboot helper mode"
for level in 2 3 4 5; do
  rc_listing=$(debugfs -R "ls -p /etc/rc${level}.d" "$ROOTFS_RAW" 2>/dev/null)
  firstboot_order=$(sed -nE 's#.*\/S([0-9]{2})ws1608-amlenc-firstboot(/.*)?#\1#p' <<<"$rc_listing" | head -n1)
  ssh_order=$(sed -nE 's#.*\/S([0-9]{2})ssh(/.*)?#\1#p' <<<"$rc_listing" | head -n1)
  [[ "$firstboot_order" =~ ^[0-9]{2}$ ]] || fail "missing firstboot rc${level} link"
  [[ "$ssh_order" =~ ^[0-9]{2}$ ]] || fail "missing ssh rc${level} link"
  ((10#$firstboot_order < 10#$ssh_order)) || fail "firstboot must precede ssh in rc${level}"
  firstboot_path="/etc/rc${level}.d/S${firstboot_order}ws1608-amlenc-firstboot"
  firstboot_link=$(debugfs -R "stat $firstboot_path" "$ROOTFS_RAW" 2>/dev/null)
  grep -q 'Type: symlink' <<<"$firstboot_link" || fail "firstboot rc${level} link type"
  grep -Fq 'Fast link dest: "../init.d/ws1608-amlenc-firstboot"' <<<"$firstboot_link" \
    || fail "firstboot rc${level} link target"
done
ssh_directory=$(debugfs -R 'ls -p /etc/ssh' "$ROOTFS_RAW" 2>/dev/null)
if grep -Eq '/ssh_host_[^/]+/' <<<"$ssh_directory"; then
  fail "preinstalled SSH host key"
fi
for forbidden in \
  /etc/rcS.d/S99ws1608-amlenc-firstboot \
  /etc/rcS.d/S01ws1608-amlenc-firstboot \
  /boot/amlenc-legacy-firstboot-started \
  /boot/amlenc-legacy-firstboot-ready \
  /boot/amlenc-legacy-firstboot-failed \
  /boot/amlenc-legacy-trial-armed \
  /boot/amlenc-legacy-dmesg.log \
  /var/lib/ws1608-amlenc/firstboot-complete \
  /tmp/ws1608-amlenc-firstboot.complete; do
  if debugfs -R "stat $forbidden" "$ROOTFS_RAW" 2>/dev/null | grep -q 'Inode:'; then
    fail "forbidden pre-firstboot path $forbidden"
  fi
done
ssh_config=$(debugfs -R 'cat /etc/ssh/sshd_config.d/ws1608-amlenc.conf' "$ROOTFS_RAW" 2>/dev/null)
grep -Fqx 'PasswordAuthentication yes' <<<"$ssh_config" || fail "SSH password policy"
grep -Fqx 'KbdInteractiveAuthentication yes' <<<"$ssh_config" || fail "SSH keyboard-interactive policy"
grep -Fqx 'PubkeyAuthentication yes' <<<"$ssh_config" || fail "SSH public-key policy"
grep -Fqx 'PermitRootLogin yes' <<<"$ssh_config" || fail "SSH root login policy"
root_shadow=$(debugfs -R 'cat /etc/shadow' "$ROOTFS_RAW" 2>/dev/null)
grep -Eq '^root:\$6\$[^:]+:' <<<"$root_shadow" || fail "root password is not SHA-512 or is missing"
authorized_keys=$(debugfs -R 'cat /root/.ssh/authorized_keys' "$ROOTFS_RAW" 2>/dev/null) || fail "SSH authorized_keys missing"
ssh_key_count=0
ssh_key_line=
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || continue
  [[ "$line" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || fail "invalid SSH public key"
  ssh_key_count=$((ssh_key_count + 1))
  ssh_key_line="$line"
done <<<"$authorized_keys"
[[ "$ssh_key_count" -eq 1 ]] || fail "expected one SSH public key"
ssh_key_sha256=$(printf '%s\n' "$ssh_key_line" | sha256sum | awk '{print $1}')
manifest_ssh_key_sha256=$(jq -er '.ssh_public_key_sha256' "$MANIFEST")
[[ "$ssh_key_sha256" == "$manifest_ssh_key_sha256" ]] || fail "SSH public key digest mismatch"
fstab=$(debugfs -R 'cat /etc/fstab' "$ROOTFS_RAW" 2>/dev/null)
grep -Fq 'LABEL=armbi_boot /boot vfat' <<<"$fstab" || fail "boot mount policy"
if debugfs -R 'stat /usr/bin/one-kvm' "$ROOTFS_RAW" 2>/dev/null | grep -q 'Inode:'; then fail "one-kvm must not be installed"; fi

limits=$(debugfs -R 'cat /usr/local/share/ws1608-amlenc/hardware-limits.json' "$ROOTFS_RAW" 2>/dev/null)
jq -e '.schema == 1 and .codec == "h264" and .pixel_format == "nv12" and .hardware_encoder_tested == false' <<<"$limits" >/dev/null \
  || fail "hardware limits metadata"

jq -e --arg base_tag "$BASE_RELEASE_TAG" --arg base_sha "$BASE_IMAGE_SHA256" \
  --arg linux "$LINUX_COMMIT" --arg initrd_sha "$legacy_initrd_sha256" '
  .schema == 1 and .kind == "ws1608-amlenc-legacy-bringup" and
  .base_release_tag == $base_tag and .base_image_sha256 == $base_sha and
  .recovery == {kernel:"6.12.28-current-meson",source:"stable-base"} and
  .legacy.kernel == "3.10.107" and .legacy.commit == $linux and .legacy.cma_mib == 64 and
  .legacy.initrd_sha256 == $initrd_sha and .boot_method == "uboot-cold-start" and
  .kexec == false and .saveenv_guard == "best-effort" and
  .early_failure_recovery == "initramfs-or-reflash" and .recovery_first == true and
  .diagnostic_included == true and .encoder.abi == 1 and
  (.encoder.commit | test("^[a-f0-9]{40}$")) and
  (.encoder.libvpcodec_sha256 | test("^[a-f0-9]{64}$")) and
  (.encoder.diagnostic_sha256 | test("^[a-f0-9]{64}$")) and
  (.ssh_public_key_sha256 | test("^[a-f0-9]{64}$")) and
  .default_login_user == "root" and .password_authentication == true and
  .hardware_boot_tested == false and .hardware_encoder_tested == false and
  .one_kvm_included == false and .hid_tested == false and .msd_tested == false and
  .stable_channel_modified == false
' "$MANIFEST" >/dev/null || fail "manifest gate"
[[ "$(sha256sum "$IMAGE" | awk '{print $1}')" == "$(jq -er '.image_sha256' "$MANIFEST")" ]] || fail "image digest"
[[ "$(sha256sum "$final_boot" | awk '{print $1}')" == "$(jq -er '.partitions.boot_sha256' "$MANIFEST")" ]] || fail "boot digest"
[[ "$(sha256sum "$final_rootfs" | awk '{print $1}')" == "$(jq -er '.partitions.rootfs_sha256' "$MANIFEST")" ]] || fail "rootfs digest"
echo "verified WS1608 recovery-first legacy bring-up image"
