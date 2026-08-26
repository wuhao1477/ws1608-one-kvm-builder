#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
mode=${1:-}
if [[ "$mode" == libvpcodec ]]; then
  exec "$ROOT_DIR/experimental/amlenc/scripts/verify-libvpcodec.sh"
fi
OUTPUT_DIR=${AMLENC_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/kernel}
SOURCE_DIR=${AMLENC_KERNEL_SOURCE:-$ROOT_DIR/.build/amlenc/kernel-source}
BUILD_DIR=${AMLENC_KERNEL_BUILD:-$ROOT_DIR/.build/amlenc/kernel-build}

[[ "$mode" == kernel ]] || { echo "unsupported verification mode: $mode" >&2; exit 2; }
for file in zImage ws1608-s805.dtb modules.tar.gz kernel.config source-manifest.json SHA256SUMS; do
  [[ -s "$OUTPUT_DIR/$file" ]] || { echo "missing kernel artifact: $file" >&2; exit 1; }
done

(cd "$OUTPUT_DIR" && sha256sum --check SHA256SUMS)
jq -e '
  .schema == 1 and
  .kernel == "3.10.107" and
  (.toolchain.gcc | test("^7\\.")) and
  (.toolchain.binutils | test("^[0-9]+\\.[0-9]+"))
' "$OUTPUT_DIR/source-manifest.json" >/dev/null
expected_patch_digest=$(
  "$ROOT_DIR/experimental/amlenc/scripts/kernel-patch-digest.sh" \
    "$ROOT_DIR/experimental/amlenc/patches/kernel"
)
jq -e --arg digest "$expected_patch_digest" '.patches_sha256 == $digest' \
  "$OUTPUT_DIR/source-manifest.json" >/dev/null
file "$OUTPUT_DIR/zImage" | grep -Eq 'ARM|Linux kernel ARM boot executable zImage'
"${CROSS_COMPILE:-arm-linux-gnueabihf-}readelf" -h "$BUILD_DIR/vmlinux" | grep -Eq 'Machine:.*ARM'
grep -aq 'Linux version 3\.10\.107' "$BUILD_DIR/vmlinux"
grep -q -- '-march=armv7-a' "$BUILD_DIR/arch/arm/vfp/.vfpmodule.o.cmd"
grep -Fqx 'CONFIG_CMA_SIZE_MBYTES=64' "$OUTPUT_DIR/kernel.config"

dtc -I dtb -O dts "$OUTPUT_DIR/ws1608-s805.dtb" > "$BUILD_DIR/ws1608-s805.verified.dts"
grep -q 'model = "WS1608 OneCloud"' "$BUILD_DIR/ws1608-s805.verified.dts"
grep -q 'amlogic,amvenc_avc' "$BUILD_DIR/ws1608-s805.verified.dts"
grep -q 'pmw_controller = "PWM_D"' "$BUILD_DIR/ws1608-s805.verified.dts"
grep -q 'amlogic,pins = "GPIODV_28"' "$BUILD_DIR/ws1608-s805.verified.dts"
! grep -q 'linux,contiguous-region' "$BUILD_DIR/ws1608-s805.verified.dts"
grep -Fq 'reserve_buff[i].buf_size = amvenc_buffspec[AMVENC_BUFFER_LEVEL_1080P].min_buffsize;' \
  "$SOURCE_DIR/drivers/amlogic/amports/encoder.c"
grep -q 'pinname = "emmc"' "$BUILD_DIR/ws1608-s805.verified.dts"
grep -q 'amlogic,meson-eth' "$BUILD_DIR/ws1608-s805.verified.dts"
grep -q 'amlogic,amhdmitx' "$BUILD_DIR/ws1608-s805.verified.dts"
grep -Eq 'port-type = <0x0+>' "$BUILD_DIR/ws1608-s805.verified.dts"
grep -Eq 'port-type = <0x0*1>' "$BUILD_DIR/ws1608-s805.verified.dts"
! grep -Eq 'Hardkernel|ODROID|sx865x' "$BUILD_DIR/ws1608-s805.verified.dts"

"$ROOT_DIR/experimental/amlenc/scripts/verify-kernel-config.sh" \
  "$SOURCE_DIR" "$OUTPUT_DIR/kernel.config"
"$ROOT_DIR/experimental/amlenc/scripts/verify-kernel-source-diff.sh" "$SOURCE_DIR"
echo "verified WS1608 S805 kernel 3.10.107 artifacts"
