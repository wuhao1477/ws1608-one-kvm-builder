#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CONFIG_FILE="$ROOT_DIR/experimental/hcodec/config/sources.env"
OUTPUT_DIR=${HCODEC_OUTPUT_DIR:-$ROOT_DIR/out/hcodec/kernel}
BUILD_DIR=${HCODEC_KERNEL_BUILD:-$ROOT_DIR/.build/hcodec/kernel-build}
EVIDENCE_DIR=${HCODEC_BASE_EVIDENCE:-$ROOT_DIR/.build/hcodec/base-evidence}
set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

for file in zImage uImage meson8b-onecloud.dtb modules.tar.xz kernel.config \
  System.map Module.symvers source-manifest.json module-signing.json SHA256SUMS; do
  [[ -s "$OUTPUT_DIR/$file" ]] || { echo "missing kernel artifact: $file" >&2; exit 1; }
done
(cd "$OUTPUT_DIR" && sha256sum --check SHA256SUMS)
"$ROOT_DIR/experimental/hcodec/scripts/verify-config-diff.sh" \
  "$EVIDENCE_DIR/kernel.config" "$OUTPUT_DIR/kernel.config"

"${CROSS_COMPILE:-arm-linux-gnueabihf-}readelf" -h "$BUILD_DIR/vmlinux" |
  grep -Eq 'Class:[[:space:]]+ELF32'
"${CROSS_COMPILE:-arm-linux-gnueabihf-}readelf" -h "$BUILD_DIR/vmlinux" |
  grep -Eq 'Machine:[[:space:]]+ARM'
grep -aq 'Linux version 6\.12\.28-current-meson' "$BUILD_DIR/vmlinux"

work=$(mktemp -d "${TMPDIR:-/tmp}/hcodec-kernel-verify.XXXXXX")
trap 'rm -rf "$work"' EXIT
tar -xJf "$OUTPUT_DIR/modules.tar.xz" -C "$work"
module=$(find "$work" -type f -name 'meson-venc.ko' -print -quit)
[[ -n "$module" ]] || { echo 'meson-venc.ko missing from modules archive' >&2; exit 1; }
modinfo -F vermagic "$module" | grep -Eq '^6\.12\.28-current-meson([[:space:]]|$)'
"${CROSS_COMPILE:-arm-linux-gnueabihf-}readelf" -h "$module" | grep -Eq 'Machine:[[:space:]]+ARM'
"$ROOT_DIR/experimental/hcodec/scripts/verify-module-signing.sh" \
  "$OUTPUT_DIR/kernel.config" "$work" "$work/module-signing.json"
cmp -s "$work/module-signing.json" "$OUTPUT_DIR/module-signing.json"

dtc -I dtb -O dts "$OUTPUT_DIR/meson8b-onecloud.dtb" >"$work/onecloud.dts"
grep -Fq 'compatible = "amlogic,meson8b-hcodec"' "$work/onecloud.dts"
grep -Fq 'status = "okay"' "$work/onecloud.dts"
grep -Fq 'reg = <0x50000 0x10000>' "$work/onecloud.dts"
! grep -Fq 'amlogic,hhi-sysctrl' "$work/onecloud.dts"

[[ "$UIMAGE_LOAD_ADDRESS" == 0x00208000 && "$UIMAGE_ENTRY_POINT" == 0x00208000 ]]
mkimage -l "$OUTPUT_DIR/uImage" >"$work/uimage.txt"
grep -Eq 'Load Address:[[:space:]]+00208000' "$work/uimage.txt"
grep -Eq 'Entry Point:[[:space:]]+00208000' "$work/uimage.txt"
node -e '
  const fs = require("fs");
  const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (m.arch !== "arm" || m.board !== "onecloud" ||
      m.kernel_release !== "6.12.28-current-meson" ||
      m.armbian_build_commit !== process.env.ARMBIAN_BUILD_COMMIT ||
      m.armbian_patches_hash !== process.env.ARMBIAN_PATCHES_HASH ||
      m.armbian_drivers_hash !== process.env.ARMBIAN_DRIVERS_HASH ||
      m.automatic_module_loading !== false ||
      m.hardware_boot_tested !== false || m.hardware_encoder_tested !== false)
    process.exit(1);
' "$OUTPUT_DIR/source-manifest.json"

echo 'verified ARMv7 6.12.28-current-meson HCODEC kernel artifacts'
