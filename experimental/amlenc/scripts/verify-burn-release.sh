#!/usr/bin/env bash
set -Eeuo pipefail

OUTPUT_DIR=${1:?usage: verify-burn-release.sh OUTPUT_DIR}

fail() { echo "burn release verification failed: $*" >&2; exit 1; }
for command in find jq sha256sum xz; do
  command -v "$command" >/dev/null || fail "missing command: $command"
done
[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || fail "invalid output directory"

entry_count=$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print | wc -l | awk '{print $1}')
regular_count=$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type f ! -type l -print | wc -l | awk '{print $1}')
[[ "$entry_count" -eq 5 && "$regular_count" -eq 5 ]] || fail "release must contain exactly five regular files"

manifest="$OUTPUT_DIR/manifest.json"
report="$OUTPUT_DIR/validation-report.json"
checksums="$OUTPUT_DIR/SHA256SUMS"
for file in "$manifest" "$report" "$checksums"; do
  [[ -f "$file" && ! -L "$file" && -s "$file" ]] || fail "missing release metadata: ${file##*/}"
done

image_name=$(jq -er '.image_name' "$manifest")
[[ "$image_name" != */* && "$image_name" == *.burn.img ]] || fail "unsafe image name"
image="$OUTPUT_DIR/$image_name"
compressed="$image.xz"
[[ -f "$image" && ! -L "$image" && -s "$image" ]] || fail "burn image is missing"
[[ -f "$compressed" && ! -L "$compressed" && -s "$compressed" ]] || fail "compressed burn image is missing"

expected=("$image_name" "$image_name.xz" SHA256SUMS manifest.json validation-report.json)
for name in "${expected[@]}"; do
  [[ -f "$OUTPUT_DIR/$name" && ! -L "$OUTPUT_DIR/$name" ]] || fail "missing release asset: $name"
done

(cd "$OUTPUT_DIR" && sha256sum --check SHA256SUMS >/dev/null) || fail "checksum verification"
xz -t "$compressed" || fail "compressed image test"
raw_sha256=$(sha256sum "$image" | awk '{print $1}')
expanded_sha256=$(xz -dc "$compressed" | sha256sum | awk '{print $1}')
[[ "$raw_sha256" == "$expanded_sha256" ]] || fail "compressed image differs from raw image"

jq -e --arg image "$image_name" --arg digest "$raw_sha256" '
  .schema == 1 and .kind == "ws1608-amlenc-burn-image" and
  .image_name == $image and .image_sha256 == $digest and
  .one_kvm_included == true and .stable_channel_modified == false and
  .hardware_boot_tested == false and .hardware_encoder_tested == false and
  (.one_kvm.version | startswith("0.2.6+ws1608amlenc."))
' "$manifest" >/dev/null || fail "manifest contract"

jq -e --arg image "$image_name" --arg raw "$raw_sha256" \
  --arg compressed_sha "$(sha256sum "$compressed" | awk '{print $1}')" \
  --arg manifest_sha "$(sha256sum "$manifest" | awk '{print $1}')" '
  .schema == 1 and .result == "pending" and
  .hardware_boot_tested == false and .hardware_encoder_tested == false and
  .assets.image == {name: $image, sha256: $raw} and
  .assets.compressed_image == {name: ($image + ".xz"), sha256: $compressed_sha} and
  .assets.manifest == {name: "manifest.json", sha256: $manifest_sha}
' "$report" >/dev/null || fail "validation report contract"

echo "verified experimental burn release assets"
