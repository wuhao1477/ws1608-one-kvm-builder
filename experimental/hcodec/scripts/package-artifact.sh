#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CONFIG_FILE="$ROOT_DIR/experimental/hcodec/config/sources.env"
KERNEL_DIR=${1:?usage: package-artifact.sh KERNEL_DIR TOOLS_DIR OUTPUT_DIR RUN_NUMBER RUN_ATTEMPT}
TOOLS_DIR=${2:?usage: package-artifact.sh KERNEL_DIR TOOLS_DIR OUTPUT_DIR RUN_NUMBER RUN_ATTEMPT}
OUTPUT_DIR=${3:?usage: package-artifact.sh KERNEL_DIR TOOLS_DIR OUTPUT_DIR RUN_NUMBER RUN_ATTEMPT}
RUN_NUMBER=${4:?usage: package-artifact.sh KERNEL_DIR TOOLS_DIR OUTPUT_DIR RUN_NUMBER RUN_ATTEMPT}
RUN_ATTEMPT=${5:?usage: package-artifact.sh KERNEL_DIR TOOLS_DIR OUTPUT_DIR RUN_NUMBER RUN_ATTEMPT}
[[ "$RUN_NUMBER" =~ ^[0-9]+$ && "$RUN_ATTEMPT" =~ ^[0-9]+$ ]] || { echo 'invalid run identity' >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a
for directory in "$KERNEL_DIR" "$TOOLS_DIR"; do [[ -d "$directory" && ! -L "$directory" ]] || { echo "invalid input: $directory" >&2; exit 1; }; done
rm -rf -- "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/stage/kernel" "$OUTPUT_DIR/stage/tools"

kernel_files=(zImage uImage meson8b-onecloud.dtb modules.tar.xz kernel.config System.map Module.symvers module-signing.json source-manifest.json SHA256SUMS)
tool_files=(meson-venc-smoke meson-venc-capture tools-manifest.json firmware-manifest.json SHA256SUMS)
for file in "${kernel_files[@]}"; do cp -p "$KERNEL_DIR/$file" "$OUTPUT_DIR/stage/kernel/$file"; done
for file in "${tool_files[@]}"; do cp -p "$TOOLS_DIR/$file" "$OUTPUT_DIR/stage/tools/$file"; done
cp -p "$ROOT_DIR/experimental/hcodec/scripts/install-artifact.sh" \
  "$OUTPUT_DIR/stage/install-artifact.sh"
find "$OUTPUT_DIR/stage" -type f \( -name '*.bin' -o -name '*.fw' \) -delete
node - "$OUTPUT_DIR/stage/manifest.json" "$RUN_NUMBER" "$RUN_ATTEMPT" "$OUTPUT_DIR/stage/kernel/source-manifest.json" "$OUTPUT_DIR/stage/tools/tools-manifest.json" <<'NODE'
const fs = require('fs');
const [file, run, attempt, sourceFile, toolsFile] = process.argv.slice(2);
const source = JSON.parse(fs.readFileSync(sourceFile, 'utf8'));
const tools = JSON.parse(fs.readFileSync(toolsFile, 'utf8'));
const kernelSums = fs.readFileSync(`${sourceFile.slice(0, sourceFile.lastIndexOf('/'))}/SHA256SUMS`, 'utf8');
const digestFor = (name) => {
  const line = kernelSums.split(/\r?\n/).find((entry) => entry.endsWith(`  ${name}`));
  return line ? line.split(/\s+/)[0] : undefined;
};
const manifest = {
  schema: 1, artifact: `ws1608-hcodec-armv7-run-${run}-${attempt}.tar.xz`,
  arch: 'arm', board: 'onecloud', kernel_base: '6.12.28-current-meson',
  kernel_release: '6.12.28-current-meson', encoder_backend: 'h264_v4l2m2m',
  base_release_tag: process.env.BASE_RELEASE_TAG,
  base_image_sha256: process.env.BASE_IMAGE_SHA256,
  linux_commit: source.linux_commit, armbian_build_commit: source.armbian_build_commit,
  driver_source_sha256: source.patches_sha256, patch_series_sha256: source.patches_sha256,
  firmware_sha256: process.env.FIRMWARE_ARCHIVE_SHA256,
  dtb_sha256: digestFor('meson8b-onecloud.dtb'),
  module_vermagic: source.kernel_release || '6.12.28-current-meson', cma_mib: 128,
  toolchain_container: source.toolchain_container, tools_abi: tools.abi,
  candidate_extraargs: 'cma=128M', automatic_module_loading: false,
  firmware_binary_included: false, hardware_boot_tested: false, hardware_encoder_tested: false
};
fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
(cd "$OUTPUT_DIR/stage" && find . -type f ! -path './SHA256SUMS' -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS)
artifact="$OUTPUT_DIR/ws1608-hcodec-armv7-run-${RUN_NUMBER}-${RUN_ATTEMPT}.tar.xz"
if tar --help 2>&1 | grep -q -- '--sort'; then
  tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -C "$OUTPUT_DIR/stage" -cJf "$artifact" .
else
  tar -C "$OUTPUT_DIR/stage" -cJf "$artifact" .
fi
cp "$OUTPUT_DIR/stage/manifest.json" "$OUTPUT_DIR/manifest.json"
rm -rf "$OUTPUT_DIR/stage"
(
  cd "$OUTPUT_DIR"
  sha256sum "$(basename "$artifact")" manifest.json >SHA256SUMS
)
"$ROOT_DIR/experimental/hcodec/scripts/verify-artifact.sh" "$OUTPUT_DIR"
