#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
OUTPUT_DIR=${1:-${HCODEC_TOOLS_OUTPUT_DIR:-$ROOT_DIR/out/hcodec/tools}}
for name in meson-venc-smoke meson-venc-capture; do
  file="$OUTPUT_DIR/$name"
  [[ -s "$file" && ! -L "$file" ]] || { echo "missing tool: $name" >&2; exit 1; }
  "${CROSS_COMPILE:-arm-linux-gnueabihf-}readelf" -h "$file" |
    grep -Eq 'Class:[[:space:]]+ELF32'
  "${CROSS_COMPILE:-arm-linux-gnueabihf-}readelf" -h "$file" |
    grep -Eq 'Machine:[[:space:]]+ARM'
  "${CROSS_COMPILE:-arm-linux-gnueabihf-}readelf" -l "$file" |
    grep -Eq 'ld-linux-armhf\.so\.3'
  "${CROSS_COMPILE:-arm-linux-gnueabihf-}readelf" -d "$file" |
    grep -Eq 'NEEDED.*libc\.so\.6'
  if command -v qemu-arm-static >/dev/null && [[ -d /usr/arm-linux-gnueabihf ]]; then
    qemu-arm-static -L /usr/arm-linux-gnueabihf "$file" --help >/dev/null
  fi
done

sha256sum "$OUTPUT_DIR"/meson-venc-smoke "$OUTPUT_DIR"/meson-venc-capture >"$OUTPUT_DIR/SHA256SUMS"
printf '%s\n' '{"schema":1,"arch":"arm","abi":"glibc","interpreter":"/lib/ld-linux-armhf.so.3","binary_included":false,"firmware_binary_included":false}' >"$OUTPUT_DIR/tools-manifest.json"
[[ -s "$OUTPUT_DIR/firmware-manifest.json" ]] || {
  echo 'firmware source manifest is required' >&2
  exit 1
}
grep -Fq '"binary_included":false' "$OUTPUT_DIR/firmware-manifest.json"
! find "$OUTPUT_DIR" -maxdepth 1 -type f \( -name '*.bin' -o -name '*.fw' \) -print -quit | grep -q .
echo 'verified ARMv7 glibc V4L2 tools'
