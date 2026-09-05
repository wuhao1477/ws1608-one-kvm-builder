#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
OUTPUT_DIR=${1:?usage: verify-artifact.sh OUTPUT_DIR}
artifact=$(find "$OUTPUT_DIR" -maxdepth 1 -type f -name 'ws1608-hcodec-armv7-run-*.tar.xz' -print)
[[ "$(printf '%s\n' "$artifact" | sed '/^$/d' | wc -l)" -eq 1 ]] || { echo 'exactly one artifact is required' >&2; exit 1; }
for file in "$OUTPUT_DIR/manifest.json" "$OUTPUT_DIR/SHA256SUMS" "$artifact"; do
  [[ -s "$file" && ! -L "$file" ]] || { echo "missing artifact file: $file" >&2; exit 1; }
done
(cd "$OUTPUT_DIR" && sha256sum --check SHA256SUMS)
work=$(mktemp -d "${TMPDIR:-/tmp}/hcodec-artifact-verify.XXXXXX")
trap 'rm -rf "$work"' EXIT
tar -xJf "$artifact" -C "$work"
unexpected_firmware=$(cd "$work" && find . -type f \( -name '*.bin' -o -name '*.fw' \) ! -path './firmware/meson8b_h264.bin' -print -quit)
[[ -z "$unexpected_firmware" ]] || { echo "unexpected firmware binary: $unexpected_firmware" >&2; exit 1; }
find "$work" -type l -print -quit | grep -q . && { echo 'symbolic links are forbidden' >&2; exit 1; } || true
allowed=$(cat <<'EOF'
./SHA256SUMS
./capture-probe.sh
./firmware/firmware-manifest.json
./firmware/meson8b_h264.bin
./install-artifact.sh
./kernel/Module.symvers
./kernel/SHA256SUMS
./kernel/System.map
./kernel/kernel.config
./kernel/meson8b-onecloud.dtb
./kernel/module-signing.json
./kernel/modules.tar.xz
./kernel/source-manifest.json
./kernel/uImage
./kernel/zImage
./manifest.json
./tools/SHA256SUMS
./tools/meson-venc-capture
./tools/meson-venc-smoke
./tools/tools-manifest.json
EOF
)
actual=$(cd "$work" && find . -type f | sort)
[[ "$actual" == "$allowed" ]] || { printf 'artifact files:\n%s\nallowed files:\n%s\n' "$actual" "$allowed" >&2; exit 1; }
for file in capture-probe.sh install-artifact.sh firmware/meson8b_h264.bin firmware/firmware-manifest.json kernel/zImage kernel/uImage kernel/meson8b-onecloud.dtb kernel/modules.tar.xz \
  kernel/kernel.config kernel/System.map kernel/Module.symvers kernel/module-signing.json kernel/source-manifest.json \
  tools/meson-venc-smoke tools/meson-venc-capture tools/tools-manifest.json \
  manifest.json SHA256SUMS; do [[ -s "$work/$file" && ! -L "$work/$file" ]] || { echo "missing payload: $file" >&2; exit 1; }; done
for file in capture-probe.sh install-artifact.sh; do
  [[ -x "$work/$file" ]] || { echo "artifact script is not executable: $file" >&2; exit 1; }
done
(cd "$work" && sha256sum --check SHA256SUMS)
node - "$work/manifest.json" <<'NODE'
const fs = require('fs');
const m = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const sha256 = /^[0-9a-f]{64}$/;
if (m.schema !== 1 || m.arch !== 'arm' || m.board !== 'onecloud' ||
    m.kernel_base !== '6.12.28-current-meson' || m.encoder_backend !== 'h264_v4l2m2m' ||
    m.kernel_release !== '6.12.28-current-meson' || m.candidate_extraargs !== 'cma=128M' ||
    m.module_vermagic !== '6.12.28-current-meson' || m.cma_mib !== 128 ||
    !sha256.test(m.driver_source_sha256) || m.driver_source_sha256 !== m.patch_series_sha256 ||
    !sha256.test(m.firmware_sha256) || !sha256.test(m.dtb_sha256) || m.tools_abi !== 'glibc' ||
    m.firmware_source_commit !== '5aed95d35d252cafc75ce613a3a0052285662de2' ||
    m.firmware_input_path !== 'drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h' ||
    m.firmware_variant !== 'meson8b_dblk' || m.firmware_binary_included !== true ||
    m.hardware_boot_tested !== false || m.hardware_encoder_tested !== false) process.exit(1);
NODE
node - "$work/firmware/firmware-manifest.json" "$work/manifest.json" <<'NODE'
const fs = require('fs');
const firmware = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const manifest = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
if (firmware.schema !== 1 || firmware.variant !== 'meson8b_dblk' ||
    firmware.commit !== '5aed95d35d252cafc75ce613a3a0052285662de2' ||
    firmware.input_path !== 'drivers/amlogic/amports/m8/ucode/encoder/h264_enc_mix_dump_dblk.h' ||
    firmware.word_count !== 2384 || firmware.output_size !== 9536 ||
    firmware.output_sha256 !== manifest.firmware_sha256 || firmware.binary_included !== true) {
  process.exit(1);
}
NODE
firmware_sha256=$(sha256sum "$work/firmware/meson8b_h264.bin" | awk '{print $1}')
manifest_firmware_sha256=$(node -p "JSON.parse(require('fs').readFileSync('$work/firmware/firmware-manifest.json','utf8')).output_sha256")
[[ "$firmware_sha256" == "$manifest_firmware_sha256" ]] || {
  echo 'firmware payload digest does not match firmware manifest' >&2
  exit 1
}
cmp -s "$OUTPUT_DIR/manifest.json" "$work/manifest.json"
echo 'verified HCODEC artifact'
