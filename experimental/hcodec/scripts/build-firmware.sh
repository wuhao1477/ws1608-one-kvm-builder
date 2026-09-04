#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CONFIG_FILE="$ROOT_DIR/experimental/hcodec/config/sources.env"
OUTPUT_DIR=${1:?usage: build-firmware.sh OUTPUT_DIR}
WORK_DIR=${HCODEC_WORK_DIR:-$ROOT_DIR/.build/hcodec}
SOURCE_DIR="$WORK_DIR/firmware-source"

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

ARCHIVE="$WORK_DIR/hardkernel-linux-$FIRMWARE_COMMIT.tar.gz"

node "$ROOT_DIR/experimental/hcodec/scripts/verify-source-locks.mjs" "$CONFIG_FILE"
command -v curl >/dev/null || { echo 'curl is required' >&2; exit 1; }
command -v tar >/dev/null || { echo 'tar is required' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'python3 is required' >&2; exit 1; }

[[ -n "$OUTPUT_DIR" && "$OUTPUT_DIR" != / ]] || { echo 'unsafe firmware output directory' >&2; exit 1; }
rm -rf -- "$SOURCE_DIR" "$OUTPUT_DIR"
mkdir -p "$SOURCE_DIR" "$OUTPUT_DIR"

mkdir -p "$WORK_DIR"
curl --fail --location --retry 5 "$FIRMWARE_ARCHIVE_URL" -o "$ARCHIVE"
printf '%s  %s\n' "$FIRMWARE_ARCHIVE_SHA256" "$ARCHIVE" | sha256sum --check
tar -xzf "$ARCHIVE" -C "$SOURCE_DIR" --strip-components=1

header="$SOURCE_DIR/$FIRMWARE_INPUT_PATH"
[[ -s "$header" && ! -L "$header" ]] || {
  echo "missing firmware input: $FIRMWARE_INPUT_PATH" >&2
  exit 1
}

python3 "$ROOT_DIR/experimental/hcodec/tools/extract-meson8b-ucode.py" \
  "$header" "$OUTPUT_DIR/meson8b_h264.bin"

output_size=$(stat -c '%s' "$OUTPUT_DIR/meson8b_h264.bin")
output_sha256=$(sha256sum "$OUTPUT_DIR/meson8b_h264.bin" | awk '{print $1}')
[[ "$output_size" == "$FIRMWARE_OUTPUT_SIZE" ]] || {
  echo "firmware output size mismatch: $output_size" >&2
  exit 1
}
[[ "$output_sha256" == "$FIRMWARE_OUTPUT_SHA256" ]] || {
  echo "firmware output digest mismatch: $output_sha256" >&2
  exit 1
}

node - "$OUTPUT_DIR/firmware-manifest.json" <<'NODE'
const fs = require('node:fs');
const [file] = process.argv.slice(2);
const values = {
  schema: 1,
  variant: 'meson8b_dblk',
  repository: process.env.FIRMWARE_REPOSITORY,
  commit: process.env.FIRMWARE_COMMIT,
  archive_sha256: process.env.FIRMWARE_ARCHIVE_SHA256,
  input_path: process.env.FIRMWARE_INPUT_PATH,
  word_count: Number(process.env.FIRMWARE_WORD_COUNT),
  output_size: Number(process.env.FIRMWARE_OUTPUT_SIZE),
  output_sha256: process.env.FIRMWARE_OUTPUT_SHA256,
  binary_included: true,
  redistribution: process.env.FIRMWARE_REDISTRIBUTION,
};
fs.writeFileSync(file, `${JSON.stringify(values, null, 2)}\n`);
NODE

printf '%s  %s\n' "$output_sha256" "$OUTPUT_DIR/meson8b_h264.bin" >"$OUTPUT_DIR/SHA256SUMS"
echo "built Meson8b firmware $output_size bytes"
