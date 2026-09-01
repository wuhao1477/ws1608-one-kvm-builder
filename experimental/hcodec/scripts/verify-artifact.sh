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
find "$work" -type f \( -name '*.bin' -o -name '*.fw' \) -print -quit | grep -q . && { echo 'firmware binary is forbidden' >&2; exit 1; } || true
find "$work" -type l -print -quit | grep -q . && { echo 'symbolic links are forbidden' >&2; exit 1; } || true
allowed=$(cat <<'EOF'
./SHA256SUMS
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
./tools/firmware-manifest.json
./tools/meson-venc-capture
./tools/meson-venc-smoke
./tools/tools-manifest.json
EOF
)
actual=$(cd "$work" && find . -type f | sort)
[[ "$actual" == "$allowed" ]] || { echo 'artifact contains files outside the whitelist' >&2; exit 1; }
for file in kernel/zImage kernel/uImage kernel/meson8b-onecloud.dtb kernel/modules.tar.xz \
  kernel/kernel.config kernel/System.map kernel/Module.symvers kernel/module-signing.json kernel/source-manifest.json \
  tools/meson-venc-smoke tools/meson-venc-capture tools/tools-manifest.json tools/firmware-manifest.json \
  manifest.json SHA256SUMS; do [[ -s "$work/$file" && ! -L "$work/$file" ]] || { echo "missing payload: $file" >&2; exit 1; }; done
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
    m.automatic_module_loading !== false || m.firmware_binary_included !== false ||
    m.hardware_boot_tested !== false || m.hardware_encoder_tested !== false) process.exit(1);
NODE
cmp -s "$OUTPUT_DIR/manifest.json" "$work/manifest.json"
echo 'verified HCODEC artifact'
