#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CONFIG_FILE="$ROOT_DIR/experimental/hcodec/config/sources.env"
OUTPUT_DIR=${HCODEC_TOOLS_OUTPUT_DIR:-$ROOT_DIR/out/hcodec/tools}
CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabihf-}
set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

command -v "${CROSS_COMPILE}gcc" >/dev/null || { echo 'ARMv7 cross compiler is required' >&2; exit 1; }
command -v "${CROSS_COMPILE}readelf" >/dev/null || { echo 'ARMv7 readelf is required' >&2; exit 1; }
rm -rf -- "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

build_one() {
  local name=$1
  local directory="$ROOT_DIR/experimental/hcodec/tools/$name"
  local build_directory
  build_directory=$(mktemp -d "$OUTPUT_DIR/.build-$name.XXXXXX")
  cp "$directory/$name.c" "$directory/Makefile" "$build_directory/"
  make -C "$build_directory" clean all \
    CC="${CROSS_COMPILE}gcc" \
    CFLAGS='-O2 -Wall -Wextra -Werror -std=c11 -march=armv7-a -mfpu=vfpv3-d16 -marm'
  cp "$build_directory/$name" "$OUTPUT_DIR/$name"
  rm -rf "$build_directory"
}

build_one meson-venc-smoke
build_one meson-venc-capture
printf '%s\n' \
  "{\"schema\":1,\"repository\":\"$FIRMWARE_REPOSITORY\",\"commit\":\"$FIRMWARE_COMMIT\",\"archive_sha256\":\"$FIRMWARE_ARCHIVE_SHA256\",\"extractor\":\"experimental/hcodec/tools/extract-meson8b-ucode.py\",\"extract_command\":\"python3 extract-meson8b-ucode.py INPUT_HEADER OUTPUT_BIN\",\"binary_included\":false,\"redistribution\":\"$FIRMWARE_REDISTRIBUTION\"}" \
  >"$OUTPUT_DIR/firmware-manifest.json"
"$ROOT_DIR/experimental/hcodec/scripts/verify-tools.sh" "$OUTPUT_DIR"
