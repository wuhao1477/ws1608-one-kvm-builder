#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CONFIG_FILE="$ROOT_DIR/experimental/amlenc/config/sources.env"
PATCH_DIR="$ROOT_DIR/experimental/amlenc/patches/libencoder"
EXPORTS_FILE="$ROOT_DIR/experimental/amlenc/config/libvpcodec.exports"
WORK_DIR=${AMLENC_WORK_DIR:-$ROOT_DIR/.build/amlenc}
SOURCE_DIR="$WORK_DIR/libencoder-source"
OUTPUT_DIR=${AMLENC_LIBVPCODEC_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/libvpcodec}
CC=${CC:-arm-linux-gnueabihf-gcc-7}
CXX=${CXX:-arm-linux-gnueabihf-g++-7}
AR=${AR:-arm-linux-gnueabihf-ar}
READELF=${READELF:-arm-linux-gnueabihf-readelf}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a
[[ "$LIBENCODER_COMMIT" =~ ^[0-9a-f]{40}$ ]]
[[ "$LIBENCODER_ARCHIVE_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$LIBENCODER_ARCHIVE_URL" == "https://codeload.github.com/khadas/libencoder/tar.gz/$LIBENCODER_COMMIT" ]]
command -v "$CC" >/dev/null
command -v "$CXX" >/dev/null
command -v "$AR" >/dev/null
command -v "$READELF" >/dev/null

compiler_version=$("$CC" -dumpfullversion -dumpversion)
compiler_major=${compiler_version%%.*}
[[ "$compiler_major" == 7 ]] || {
  echo "M8 userspace build requires GCC 7.x; found $compiler_version" >&2
  exit 1
}

mkdir -p "$WORK_DIR"
archive="$WORK_DIR/libencoder-$LIBENCODER_COMMIT.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 5 "$LIBENCODER_ARCHIVE_URL" -o "$archive"
fi
printf '%s  %s\n' "$LIBENCODER_ARCHIVE_SHA256" "$archive" | sha256sum --check

rm -rf "$SOURCE_DIR" "$OUTPUT_DIR"
mkdir -p "$SOURCE_DIR" "$OUTPUT_DIR"
tar -xzf "$archive" -C "$SOURCE_DIR" --strip-components=1
git -C "$SOURCE_DIR" init -q
git -C "$SOURCE_DIR" add --all
git -C "$SOURCE_DIR" -c user.name=builder -c user.email=noreply@github.com \
  -c commit.gpgsign=false commit -q -m baseline
# Normalize only the files touched by the patch set. The archive contains a few
# isolated CR bytes; explicit conversion keeps strict application deterministic.
for source_file in enc_api.cpp libvpcodec.cpp; do
  sed -i 's/\r$//' "$SOURCE_DIR/amvenc_264/bjunion_enc/$source_file"
done
for patch in "$PATCH_DIR"/*.patch; do
  git -C "$SOURCE_DIR" apply --check "$patch"
  git -C "$SOURCE_DIR" apply "$patch"
done
cmp -s "$EXPORTS_FILE" "$SOURCE_DIR/amvenc_264/bjunion_enc/libvpcodec.exports"
git -C "$SOURCE_DIR" add --all
git -C "$SOURCE_DIR" -c user.name=builder -c user.email=noreply@github.com \
  -c commit.gpgsign=false commit -q -m patched-source

make -C "$SOURCE_DIR/amvenc_264/bjunion_enc" -j"$JOBS" \
  CC="$CC" CXX="$CXX" AR="$AR"
"$CXX" \
  -O2 -marm -march=armv7-a -mfpu=neon -mfloat-abi=hard \
  "$ROOT_DIR/experimental/amlenc/tools/amlenc-m8-diag.cpp" \
  -ldl -o "$OUTPUT_DIR/amlenc-m8-diag"
cp "$SOURCE_DIR/amvenc_264/bjunion_enc/libvpcodec.so" "$OUTPUT_DIR/libvpcodec.so"
make -C "$SOURCE_DIR/amvenc_264/bjunion_enc" clean

patch_digest=$("$ROOT_DIR/experimental/amlenc/scripts/libencoder-patch-digest.sh" "$PATCH_DIR")
cat > "$OUTPUT_DIR/source-manifest.json" <<EOF
{"schema":1,"repository":"$LIBENCODER_REPOSITORY","commit":"$LIBENCODER_COMMIT","archive_sha256":"$LIBENCODER_ARCHIVE_SHA256","patches_sha256":"$patch_digest","architecture":"armhf","implementation":"M8/M8_FAST H.264","abi":1,"redistribution":"local-test-only","toolchain":{"gcc":"$compiler_version"}}
EOF
(
  cd "$OUTPUT_DIR"
  sha256sum libvpcodec.so amlenc-m8-diag source-manifest.json > SHA256SUMS
)

AMLENC_LIBENCODER_SOURCE="$SOURCE_DIR" CC="$CC" READELF="$READELF" \
  "$ROOT_DIR/experimental/amlenc/scripts/verify-libvpcodec.sh"
