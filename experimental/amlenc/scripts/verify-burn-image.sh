#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
IMAGE=${IMAGE:?IMAGE is required}
MANIFEST=${MANIFEST:?MANIFEST is required}
BASE_IMAGE=${BASE_IMAGE:?BASE_IMAGE is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
VERIFY_DIR=${VERIFY_DIR:-$ROOT_DIR/.build/amlenc/burn-verify}

fail() { echo "burn image verification failed: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "missing command: $1"; }
basename_only() { [[ "$1" != /* && "$1" != *'/'* && "$1" != *'\\'* && "$1" != . && "$1" != .. ]] || fail "unsafe package entry"; }
for command in awk cmp debugfs e2fsck file jq mcopy mkimage node sha1sum sha256sum stat; do need "$command"; done
[[ -f "$IMAGE" && ! -L "$IMAGE" ]] || fail "image missing"
[[ -f "$MANIFEST" && ! -L "$MANIFEST" ]] || fail "manifest missing"
[[ -f "$BASE_IMAGE" && ! -L "$BASE_IMAGE" ]] || fail "base image missing"
[[ -x "$AMLIMG_BIN" ]] || fail "AmlImg is not executable"
mkdir -p "$VERIFY_DIR"
rm -rf "$VERIFY_DIR/final" "$VERIFY_DIR/base"
mkdir -p "$VERIFY_DIR/final" "$VERIFY_DIR/base"
"$AMLIMG_BIN" unpack "$IMAGE" "$VERIFY_DIR/final"
"$AMLIMG_BIN" unpack "$BASE_IMAGE" "$VERIFY_DIR/base"

jq -e '.schema == 1 and .kind == "ws1608-amlenc-burn-image" and .hardware_encoder_tested == false and .hardware_boot_tested == false and .one_kvm_included == true and .stable_channel_modified == false' "$MANIFEST" >/dev/null || fail "manifest gate"
diff -u "$VERIFY_DIR/base/commands.txt" "$VERIFY_DIR/final/commands.txt" >/dev/null || fail "commands.txt changed"
while IFS=: read -r type name image_type filename; do
  basename_only "$filename"
  if [[ "$type" == PARTITION ]]; then
    if [[ "$name" != rootfs && "$name" != boot ]]; then cmp "$VERIFY_DIR/base/$filename" "$VERIFY_DIR/final/$filename" || fail "$name partition changed"; fi
  elif [[ "$type" == VERIFY ]]; then
    [[ -f "$VERIFY_DIR/final/$filename" ]] || fail "missing verify entry"
  fi
done <"$VERIFY_DIR/final/commands.txt"

declare -A partition verify_file
while IFS=: read -r type name image_type filename; do
  if [[ "$type" == PARTITION ]]; then partition[$name]="$VERIFY_DIR/final/$filename"; fi
  if [[ "$type" == VERIFY ]]; then verify_file[$name]="$VERIFY_DIR/final/$filename"; fi
done <"$VERIFY_DIR/final/commands.txt"
for name in boot rootfs; do
  [[ -f "${partition[$name]:-}" && -f "${verify_file[$name]:-}" ]] || fail "missing $name partition or verify"
  expected=$(<"${verify_file[$name]}")
  actual="sha1sum $(sha1sum "${partition[$name]}" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || fail "$name VERIFY mismatch"
done

rootfs_raw="$VERIFY_DIR/rootfs.raw"
boot_raw="$VERIFY_DIR/boot.raw"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "${partition[rootfs]}" "$rootfs_raw"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "${partition[boot]}" "$boot_raw"
e2fsck -fn "$rootfs_raw" >/dev/null || fail "rootfs filesystem check"
mcopy -i "$boot_raw" ::uImage ::boot.scr ::boot.cmd ::amlencEnv.txt ::ws1608-s805.dtb "$VERIFY_DIR/" >/dev/null
mkimage -l "$VERIFY_DIR/uImage" | grep -q 'Linux-3.10.107-WS1608-AMLENC' || fail "kernel image identity"
grep -Fqx 'bootm 0x20800000 - 0x21800000' "$VERIFY_DIR/boot.cmd" || fail "boot command"
debugfs -R 'stat /usr/bin/one-kvm' "$rootfs_raw" 2>/dev/null | grep -q 'Type: regular' || fail "One-KVM binary missing"
debugfs -R 'stat /usr/lib/one-kvm/libvpcodec.so' "$rootfs_raw" 2>/dev/null | grep -q 'Type: regular' || fail "One-KVM encoder library missing"
debugfs -R 'stat /etc/init.d/one-kvm' "$rootfs_raw" 2>/dev/null | grep -q 'Mode:  0755' || fail "One-KVM init script missing"
debugfs -R 'stat /etc/rc2.d/S99one-kvm' "$rootfs_raw" 2>/dev/null | grep -q 'Type: symlink' || fail "One-KVM boot link missing"
debugfs -R 'dump /usr/bin/one-kvm /tmp/ws1608-one-kvm-verify' "$rootfs_raw" >/dev/null 2>&1
file /tmp/ws1608-one-kvm-verify | grep -Eq 'ELF 32-bit LSB.*ARM.*EABI5.*dynamically linked' || fail "One-KVM ELF identity"
rm -f /tmp/ws1608-one-kvm-verify
[[ "$(sha256sum "$IMAGE" | awk '{print $1}')" == "$(jq -er '.image_sha256' "$MANIFEST")" ]] || fail "image digest mismatch"
echo "verified WS1608 AMLENC burn image"
