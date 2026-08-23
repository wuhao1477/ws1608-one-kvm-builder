#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
OUTPUT_DIR=${OUTPUT_DIR:?OUTPUT_DIR is required}
IMAGE_NAME=${IMAGE_NAME:?IMAGE_NAME is required}
MANIFEST_NAME=${MANIFEST_NAME:-manifest.json}
REPORT_NAME=${REPORT_NAME:-validation-report.json}

[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || exit 1
[[ "$IMAGE_NAME" != */* && "$MANIFEST_NAME" != */* && "$REPORT_NAME" != */* ]] || exit 1
command -v xz >/dev/null
command -v sha256sum >/dev/null
image="$OUTPUT_DIR/$IMAGE_NAME"
manifest="$OUTPUT_DIR/$MANIFEST_NAME"
report="$OUTPUT_DIR/$REPORT_NAME"
[[ -s "$image" && -s "$manifest" ]] || exit 1
jq -e '
  .stable_base_preserved == true and .kernel.source == "stable-base" and
  (.build_tag | test("^ws1608-amlenc-exp-0\\.2\\.6-v[0-9]+-k6\\.12\\.28-b[0-9]{6}$")) and
  .hardware_encoder_tested == false and .hardware_boot_tested == false and
  .one_kvm_included == true
' "$manifest" >/dev/null
xz -T0 -9e -c "$image" >"$image.xz.tmp"
mv "$image.xz.tmp" "$image.xz"
image_sha256=$(sha256sum "$image" | awk '{print $1}')
xz_sha256=$(sha256sum "$image.xz" | awk '{print $1}')
manifest_sha256=$(sha256sum "$manifest" | awk '{print $1}')
jq -n --arg result pending --arg image "$IMAGE_NAME" --arg image_sha256 "$image_sha256" \
  --arg xz "$IMAGE_NAME.xz" --arg xz_sha256 "$xz_sha256" \
  --arg manifest "$MANIFEST_NAME" --arg manifest_sha256 "$manifest_sha256" \
  '{schema: 1, result: $result, hardware_boot_tested: false, hardware_encoder_tested: false,
    assets: {image: {name: $image, sha256: $image_sha256}, compressed_image: {name: $xz, sha256: $xz_sha256}, manifest: {name: $manifest, sha256: $manifest_sha256}}}' >"$report"
(cd "$OUTPUT_DIR" && sha256sum "$IMAGE_NAME" "$IMAGE_NAME.xz" "$MANIFEST_NAME" "$REPORT_NAME" >SHA256SUMS)
echo "packaged experimental burn metadata in $OUTPUT_DIR"
