#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CONFIG_FILE="$ROOT_DIR/experimental/amlenc/config/sources.env"
PATCH_DIR="$ROOT_DIR/experimental/amlenc/patches/kernel"
WORK_DIR=${AMLENC_WORK_DIR:-$ROOT_DIR/.build/amlenc}
SOURCE_DIR="$WORK_DIR/kernel-source"
BUILD_DIR="$WORK_DIR/kernel-build"
OUTPUT_DIR=${AMLENC_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/kernel}
CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabihf-}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a
node "$ROOT_DIR/experimental/amlenc/scripts/verify-source-locks.mjs" "$CONFIG_FILE"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
case_probe="$WORK_DIR/case-sensitive-probe"
case_probe_upper="$WORK_DIR/CASE-SENSITIVE-PROBE"
printf probe > "$case_probe"
if [[ -e "$case_probe_upper" ]]; then
  rm -f "$case_probe" "$case_probe_upper"
  echo "Linux 3.10 source extraction requires a case-sensitive work directory: $WORK_DIR" >&2
  exit 1
fi
rm -f "$case_probe"

command -v "${CROSS_COMPILE}gcc" >/dev/null
command -v "${CROSS_COMPILE}as" >/dev/null
compiler_version=$("${CROSS_COMPILE}gcc" -dumpfullversion -dumpversion)
compiler_major=${compiler_version%%.*}
[[ "$compiler_major" =~ ^[0-9]+$ && "$compiler_major" -ge 7 && "$compiler_major" -le 7 ]] || {
  echo "Linux 3.10 ARM build requires GCC 7.x; found $compiler_version" >&2
  exit 1
}
binutils_version=$("${CROSS_COMPILE}as" --version | sed -n '1s/.* //p')

archive="$WORK_DIR/linux-$LINUX_COMMIT.tar.gz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 5 "$LINUX_ARCHIVE_URL" -o "$archive"
fi
printf '%s  %s\n' "$LINUX_ARCHIVE_SHA256" "$archive" | sha256sum --check

rm -rf "$SOURCE_DIR" "$BUILD_DIR"
mkdir -p "$SOURCE_DIR" "$BUILD_DIR"
tar -xzf "$archive" -C "$SOURCE_DIR" --strip-components=1
git -C "$SOURCE_DIR" init -q
git -C "$SOURCE_DIR" add --all
git -C "$SOURCE_DIR" -c user.name=builder -c user.email=noreply@github.com \
  -c commit.gpgsign=false commit -q -m baseline
for patch in "$PATCH_DIR"/0001-*.patch "$PATCH_DIR"/0002-*.patch; do
  git -C "$SOURCE_DIR" apply --check "$patch"
  git -C "$SOURCE_DIR" apply "$patch"
done

make_args=(ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" O="$BUILD_DIR" \
  HOSTCFLAGS="-O2 -fcommon" KCFLAGS="-march=armv7-a")
make -C "$SOURCE_DIR" "${make_args[@]}" odroidc_defconfig
scripts_config="$SOURCE_DIR/scripts/config"
"$scripts_config" --file "$BUILD_DIR/.config" \
  --enable CMA --enable AMLOGIC_ION --enable USB_GADGET --enable AM_ENCODER \
  --disable MALI400 --disable MALI450 --disable MALI400_UMP \
  --disable FB_AMLOGIC_UMP --disable FB_TFT --disable UMP
"$scripts_config" --file "$BUILD_DIR/.config" \
  --enable CMA_SIZE_SEL_MBYTES --disable CMA_SIZE_SEL_PERCENTAGE \
  --disable CMA_SIZE_SEL_MIN --disable CMA_SIZE_SEL_MAX \
  --set-val CMA_SIZE_MBYTES 64
make -C "$SOURCE_DIR" "${make_args[@]}" olddefconfig
make -C "$SOURCE_DIR" "${make_args[@]}" -j"$JOBS" zImage meson8b_odroidc.dtb modules

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/modules"
make -C "$SOURCE_DIR" "${make_args[@]}" INSTALL_MOD_PATH="$OUTPUT_DIR/modules" modules_install
cp "$BUILD_DIR/arch/arm/boot/zImage" "$OUTPUT_DIR/zImage"
cp "$BUILD_DIR/arch/arm/boot/dts/meson8b_odroidc.dtb" "$OUTPUT_DIR/ws1608-s805.dtb"
cp "$BUILD_DIR/.config" "$OUTPUT_DIR/kernel.config"
tar -C "$OUTPUT_DIR/modules" -czf "$OUTPUT_DIR/modules.tar.gz" .
rm -rf "$OUTPUT_DIR/modules"

patch_digest=$("$ROOT_DIR/experimental/amlenc/scripts/kernel-patch-digest.sh" "$PATCH_DIR")
cat > "$OUTPUT_DIR/source-manifest.json" <<EOF
{"schema":1,"repository":"$LINUX_REPOSITORY","commit":"$LINUX_COMMIT","archive_sha256":"$LINUX_ARCHIVE_SHA256","patches_sha256":"$patch_digest","kernel":"$KERNEL_VERSION","board":"WS1608 OneCloud","toolchain":{"gcc":"$compiler_version","binutils":"$binutils_version"}}
EOF
(
  cd "$OUTPUT_DIR"
  sha256sum zImage ws1608-s805.dtb modules.tar.gz kernel.config source-manifest.json > SHA256SUMS
)

"$ROOT_DIR/experimental/amlenc/scripts/verify-kernel-source-diff.sh" "$SOURCE_DIR"

AMLENC_KERNEL_SOURCE="$SOURCE_DIR" AMLENC_KERNEL_BUILD="$BUILD_DIR" \
  "$ROOT_DIR/experimental/amlenc/scripts/verify-build.sh" kernel
