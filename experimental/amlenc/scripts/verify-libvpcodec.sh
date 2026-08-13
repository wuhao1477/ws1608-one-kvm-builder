#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
PATCH_DIR="$ROOT_DIR/experimental/amlenc/patches/libencoder"
OUTPUT_DIR=${AMLENC_LIBVPCODEC_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/libvpcodec}
SOURCE_DIR=${AMLENC_LIBENCODER_SOURCE:-$ROOT_DIR/.build/amlenc/libencoder-source}
CC=${CC:-arm-linux-gnueabihf-gcc-7}
READELF=${READELF:-arm-linux-gnueabihf-readelf}
readelf=$READELF

for file in libvpcodec.so amlenc-m8-diag source-manifest.json SHA256SUMS; do
  [[ -s "$OUTPUT_DIR/$file" ]] || { echo "missing libvpcodec artifact: $file" >&2; exit 1; }
done
(cd "$OUTPUT_DIR" && sha256sum --check SHA256SUMS)

for artifact in libvpcodec.so amlenc-m8-diag; do
  header=$("$readelf" -h "$OUTPUT_DIR/$artifact")
  grep -q 'Class:.*ELF32' <<<"$header"
  grep -q 'Machine:.*ARM' <<<"$header"
  grep -q 'hard-float ABI' <<<"$header"
done

mapfile -t exports < <(
  "$readelf" -Ws "$OUTPUT_DIR/libvpcodec.so" \
    | awk '$4 == "FUNC" && $5 == "GLOBAL" && $7 != "UND" {sub(/@@.*/, "", $8); print $8}' \
    | LC_ALL=C sort -u
)
expected=(one_kvm_amlenc_abi_version vl_video_encoder_destory vl_video_encoder_encode vl_video_encoder_init)
[[ "${exports[*]}" == "${expected[*]}" ]] || {
  printf 'unexpected libvpcodec exports: %s\n' "${exports[*]}" >&2
  exit 1
}

qemu_arm=${QEMU_ARM:-qemu-arm}
sysroot=$("$CC" -print-sysroot)
[[ -n "$sysroot" && "$sysroot" != / ]] || sysroot=/usr/arm-linux-gnueabihf
"$qemu_arm" -L "$sysroot" "$OUTPUT_DIR/amlenc-m8-diag" \
  --abi-check "$OUTPUT_DIR/libvpcodec.so"

expected_patch_digest=$("$ROOT_DIR/experimental/amlenc/scripts/libencoder-patch-digest.sh" "$PATCH_DIR")
jq -e --arg digest "$expected_patch_digest" '
  .schema == 1 and .architecture == "armhf" and .abi == 1 and
  .redistribution == "local-test-only" and .patches_sha256 == $digest and
  (.toolchain.gcc | test("^7\\."))
' "$OUTPUT_DIR/source-manifest.json" >/dev/null

git -C "$SOURCE_DIR" diff --check
[[ -z "$(git -C "$SOURCE_DIR" status --porcelain=v1 --untracked-files=all)" ]] || {
  git -C "$SOURCE_DIR" status --short --untracked-files=all >&2
  exit 1
}
! grep -R -n -E 'encode_poll\([^,]+,[[:space:]]*-1\)' \
  "$SOURCE_DIR/amvenc_264/bjunion_enc/enc/m8_enc" \
  "$SOURCE_DIR/amvenc_264/bjunion_enc/enc/m8_enc_fast"
! grep -n -E 'enc/gx_enc_fast|h265|hevc' "$SOURCE_DIR/amvenc_264/bjunion_enc/Makefile"
echo "verified M8 One-KVM AMLENC ABI v1 local-test-only artifacts"
