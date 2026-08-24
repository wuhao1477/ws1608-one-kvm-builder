#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source "$ROOT_DIR/config/base.env"

IMAGE=${IMAGE:?IMAGE is required}
MANIFEST=${MANIFEST:?MANIFEST is required}
BASE_IMAGE=${BASE_IMAGE:?BASE_IMAGE is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
VERIFY_DIR=${VERIFY_DIR:-$ROOT_DIR/.build/amlenc/burn-verify}

fail() { echo "burn image verification failed: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "missing command: $1"; }
basename_only() { [[ -n "$1" && "$1" != /* && "$1" != *'/'* && "$1" != *'\\'* && "$1" != . && "$1" != .. ]] || fail "unsafe package entry"; }
for command in awk cmp debugfs e2fsck file grep jq node realpath sha1sum sha256sum; do need "$command"; done
[[ -f "$IMAGE" && ! -L "$IMAGE" ]] || fail "image missing"
[[ -f "$MANIFEST" && ! -L "$MANIFEST" ]] || fail "manifest missing"
[[ -f "$BASE_IMAGE" && ! -L "$BASE_IMAGE" ]] || fail "base image missing"
[[ -x "$AMLIMG_BIN" ]] || fail "AmlImg is not executable"
verify_resolved=$(realpath -m -- "$VERIFY_DIR")
[[ "$verify_resolved" != / && "$verify_resolved" != "$ROOT_DIR" ]] || fail "unsafe verify directory"

mkdir -p "$VERIFY_DIR"
[[ ! -L "$VERIFY_DIR" ]] || fail "verify directory must not be a symlink"
rm -rf "$VERIFY_DIR/final" "$VERIFY_DIR/base"
mkdir -p "$VERIFY_DIR/final" "$VERIFY_DIR/base"
"$AMLIMG_BIN" unpack "$IMAGE" "$VERIFY_DIR/final"
"$AMLIMG_BIN" unpack "$BASE_IMAGE" "$VERIFY_DIR/base"

jq -e \
  --arg base_tag "$BASE_RELEASE_TAG" --arg base_name "$BASE_IMAGE_NAME" \
  --arg base_sha256 "$BASE_IMAGE_SHA256" --arg base_kernel "$BASE_KERNEL" '
  .schema == 1 and .kind == "ws1608-amlenc-burn-image" and
  .stable_base_preserved == true and
  .base_release_tag == $base_tag and .base_image_name == $base_name and
  .base_image_sha256 == $base_sha256 and
  (.build_tag | test("^ws1608-amlenc-exp-0\\.2\\.6-v[0-9]+-k6\\.12\\.28-b[0-9]{6}$")) and
  .kernel == {version: $base_kernel, source: "stable-base"} and
  .kernel.version != "3.10.107" and
  .encoder.driver_status == "research-only" and
  .codec_baseline == {software:["h264","h265","vp8","vp9"],hardware:[],runtime_verified:true} and
  .hardware_encoder_tested == false and .hardware_boot_tested == false and
  .one_kvm_included == true and .stable_channel_modified == false
' "$MANIFEST" >/dev/null || fail "manifest gate"

cmp "$VERIFY_DIR/base/commands.txt" "$VERIFY_DIR/final/commands.txt" || fail "commands.txt changed"
while IFS=: read -r type name image_type filename; do
  basename_only "$filename"
  if [[ "$name" != rootfs ]]; then
    cmp "$VERIFY_DIR/base/$filename" "$VERIFY_DIR/final/$filename" || fail "$type $name changed"
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

cmp --silent "$VERIFY_DIR/base/${partition[rootfs]##*/}" "${partition[rootfs]}" && fail "rootfs was not changed"
boot_sha256=$(sha256sum "${partition[boot]}" | awk '{print $1}')
[[ "$boot_sha256" == "$(jq -er '.boot_partition_sha256' "$MANIFEST")" ]] || fail "boot digest mismatch"

rootfs_raw="$VERIFY_DIR/rootfs.raw"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "${partition[rootfs]}" "$rootfs_raw"
e2fsck -fn "$rootfs_raw" >/dev/null || fail "rootfs filesystem check"
debugfs -R 'stat /usr/bin/one-kvm' "$rootfs_raw" 2>/dev/null | grep -q 'Type: regular' || fail "One-KVM binary missing"
debugfs -R 'stat /usr/lib/one-kvm/libvpcodec.so' "$rootfs_raw" 2>/dev/null | grep -q 'Type: regular' || fail "One-KVM encoder library missing"
debugfs -R 'stat /usr/lib/one-kvm/amlenc-m8-diag' "$rootfs_raw" 2>/dev/null | grep -q 'Type: regular' || fail "AMLENC diagnostic missing"
debugfs -R 'stat /lib/systemd/system/one-kvm.service' "$rootfs_raw" 2>/dev/null | grep -q 'Type: regular' || fail "One-KVM service missing"
debugfs -R 'stat /etc/systemd/system/multi-user.target.wants/one-kvm.service' "$rootfs_raw" 2>/dev/null | grep -q 'Type: symlink' || fail "One-KVM boot link missing"
service_contents=$(debugfs -R 'cat /lib/systemd/system/one-kvm.service' "$rootfs_raw" 2>/dev/null)
grep -Fqx 'Environment=ONE_KVM_AMLENC_H264_LIB=/usr/lib/one-kvm/libvpcodec.so' <<<"$service_contents" || fail "AMLENC library environment missing"
if grep -Fq 'ONE_KVM_AMLENC_SMOKE_TEST' <<<"$service_contents"; then fail "hardware smoke test enabled by default"; fi
files_dir="$VERIFY_DIR/installed-files"
rm -rf "$files_dir"
mkdir -p "$files_dir/usr/bin" "$files_dir/usr/lib/one-kvm" "$files_dir/usr/share/doc/one-kvm"
for guest in \
  usr/bin/one-kvm \
  usr/lib/one-kvm/libvpcodec.so \
  usr/lib/one-kvm/amlenc-m8-diag \
  usr/share/doc/one-kvm/ws1608-amlenc-build.json \
  usr/share/doc/one-kvm/SHA256SUMS; do
  debugfs -R "dump /$guest $files_dir/$guest" "$rootfs_raw" >/dev/null 2>&1 || fail "could not extract $guest"
done
(cd "$files_dir" && sha256sum --check usr/share/doc/one-kvm/SHA256SUMS >/dev/null) || fail "installed package checksum mismatch"
metadata="$files_dir/usr/share/doc/one-kvm/ws1608-amlenc-build.json"
jq -e --arg version "$(jq -er '.one_kvm.version' "$MANIFEST")" '
  .package_version == $version and .amlenc_smoke_test_default == false and
  .software_codecs == [
    {id:"h264",encoder:"libx264",decoder:"h264",hardware:false},
    {id:"h265",encoder:"libx265",decoder:"hevc",hardware:false},
    {id:"vp8",encoder:"libvpx",decoder:"vp8",hardware:false},
    {id:"vp9",encoder:"libvpx-vp9",decoder:"vp9",hardware:false}
  ] and .hardware_encoder_tested == false and .stable_channel_modified == false
' "$metadata" >/dev/null || fail "installed package provenance mismatch"

binary="$files_dir/usr/bin/one-kvm"
file "$binary" | grep -Eq 'ELF 32-bit LSB.*ARM.*EABI5.*dynamically linked' || fail "One-KVM ELF identity"
[[ "$(sha256sum "$IMAGE" | awk '{print $1}')" == "$(jq -er '.image_sha256' "$MANIFEST")" ]] || fail "image digest mismatch"
echo "verified WS1608 AMLENC burn image with stable boot chain"
