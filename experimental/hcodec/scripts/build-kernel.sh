#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CONFIG_FILE="$ROOT_DIR/experimental/hcodec/config/sources.env"
PATCH_DIR="$ROOT_DIR/experimental/hcodec/patches/linux-6.12"
WORK_DIR=${HCODEC_WORK_DIR:-$ROOT_DIR/.build/hcodec}
EVIDENCE_DIR=${HCODEC_BASE_EVIDENCE:-$WORK_DIR/base-evidence}
OUTPUT_DIR=${HCODEC_OUTPUT_DIR:-$ROOT_DIR/out/hcodec/kernel}
BUILD_DIR="$WORK_DIR/kernel-build"
ARMBIAN_DIR="$WORK_DIR/armbian-build"
SOURCE_DIR="$ARMBIAN_DIR/cache/sources/linux-kernel-worktree/6.12__meson__armhf"
CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabihf-}
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a
node "$ROOT_DIR/experimental/hcodec/scripts/verify-source-locks.mjs" "$CONFIG_FILE"

for file in evidence-manifest.json kernel.config; do
  [[ -s "$EVIDENCE_DIR/$file" && ! -L "$EVIDENCE_DIR/$file" ]] || {
    echo "missing base evidence: $file" >&2
    exit 1
  }
done
printf '%s  %s\n' "$KERNEL_CONFIG_SHA256" "$EVIDENCE_DIR/kernel.config" | sha256sum --check
command -v "${CROSS_COMPILE}gcc" >/dev/null
command -v mkimage >/dev/null
command -v modinfo >/dev/null

reset_dir() {
  local directory=$1
  [[ -n "$directory" && "$directory" != / && "$directory" != "$ROOT_DIR" ]] || {
    echo "unsafe build directory: $directory" >&2
    exit 1
  }
  rm -rf -- "$directory"
  mkdir -p "$directory"
}
mkdir -p "$WORK_DIR"
reset_dir "$BUILD_DIR"
reset_dir "$ARMBIAN_DIR"
reset_dir "$OUTPUT_DIR"

armbian_archive="$WORK_DIR/armbian-build-$ARMBIAN_BUILD_COMMIT.tar.gz"
[[ -f "$armbian_archive" ]] || curl --fail --location --retry 5 "$ARMBIAN_BUILD_ARCHIVE_URL" -o "$armbian_archive"
printf '%s  %s\n' "$ARMBIAN_BUILD_ARCHIVE_SHA256" "$armbian_archive" | sha256sum --check
tar -xzf "$armbian_archive" -C "$ARMBIAN_DIR" --strip-components=1

staging="$ARMBIAN_DIR/userpatches/kernel/archive/meson-6.12"
mkdir -p "$staging"
for patch in "$PATCH_DIR"/*.patch; do
  cp "$patch" "$staging/zz-hcodec-${patch##*/}"
done
(
  cd "$ARMBIAN_DIR"
  # Armbian owns source checkout, driver harness and patch ordering.
  ALLOW_ROOT=yes PRE_PREPARED_HOST=yes ARMBIAN_INSIDE_DOCKERFILE_BUILD=yes \
    SKIP_LOG_ARCHIVE=yes ./compile.sh kernel-patches-to-git \
    BOARD=onecloud BRANCH=current RELEASE=trixie ROOTFS_TYPE=nfs \
    KERNEL_CONFIGURE=no SHARE_LOG=no
)
[[ -e "$SOURCE_DIR/.git" && ! -L "$SOURCE_DIR/.git" ]] || {
  echo 'Armbian kernel worktree missing' >&2
  exit 1
}
git -C "$SOURCE_DIR" merge-base --is-ancestor "$LINUX_COMMIT" HEAD || {
  echo 'Armbian kernel worktree does not descend from the locked Linux commit' >&2
  exit 1
}
git -C "$SOURCE_DIR" clean -f -- '*.orig'
[[ -z "$(git -C "$SOURCE_DIR" status --porcelain=v1 --untracked-files=all)" ]] || {
  echo 'Armbian kernel worktree is not clean' >&2
  echo 'Armbian kernel worktree status:' >&2
  git -C "$SOURCE_DIR" status --porcelain=v1 --untracked-files=all >&2
  exit 1
}
shopt -s nullglob
driver_patches=("$ARMBIAN_DIR"/cache/patch/kernel-drivers/*.patch)
shopt -u nullglob
[[ "${#driver_patches[@]}" -eq 1 && "${driver_patches[0]}" == *"$ARMBIAN_DRIVERS_HASH"* ]] || {
  echo 'Armbian driver patch does not match the stable evidence' >&2
  exit 1
}

make_args=(ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" O="$BUILD_DIR" \
  LOCALVERSION=-current-meson KBUILD_BUILD_VERSION=1 \
  KBUILD_BUILD_TIMESTAMP='Thu Jan 1 00:00:00 UTC 1970' \
  KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=github-actions)
cp "$EVIDENCE_DIR/kernel.config" "$BUILD_DIR/.config"
# Candidate config: CONFIG_VIDEO_MESON_VENC=m
"$SOURCE_DIR/scripts/config" --file "$BUILD_DIR/.config" --module VIDEO_MESON_VENC
make -C "$SOURCE_DIR" "${make_args[@]}" olddefconfig
"$ROOT_DIR/experimental/hcodec/scripts/verify-config-diff.sh" \
  "$EVIDENCE_DIR/kernel.config" "$BUILD_DIR/.config"
make -C "$SOURCE_DIR" "${make_args[@]}" -j"$JOBS" \
  zImage modules amlogic/meson8b-onecloud.dtb

modules_root="$WORK_DIR/modules-root"
reset_dir "$modules_root"
make -C "$SOURCE_DIR" "${make_args[@]}" \
  INSTALL_MOD_PATH="$modules_root" modules_install
find "$modules_root" -type l -delete

cp "$BUILD_DIR/arch/arm/boot/zImage" "$OUTPUT_DIR/zImage"
cp "$BUILD_DIR/arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb" \
  "$OUTPUT_DIR/meson8b-onecloud.dtb"
cp "$BUILD_DIR/.config" "$OUTPUT_DIR/kernel.config"
cp "$BUILD_DIR/System.map" "$OUTPUT_DIR/System.map"
cp "$BUILD_DIR/Module.symvers" "$OUTPUT_DIR/Module.symvers"
mkimage -A arm -O linux -T kernel -C none \
  -a "$UIMAGE_LOAD_ADDRESS" -e "$UIMAGE_ENTRY_POINT" \
  -n "Linux-$KERNEL_RELEASE" -d "$OUTPUT_DIR/zImage" "$OUTPUT_DIR/uImage"
tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  -C "$modules_root" -cJf "$OUTPUT_DIR/modules.tar.xz" .

"$ROOT_DIR/experimental/hcodec/scripts/verify-module-signing.sh" \
  "$OUTPUT_DIR/kernel.config" "$modules_root" "$OUTPUT_DIR/module-signing.json"
patch_digest=$("$ROOT_DIR/experimental/hcodec/scripts/patch-digest.sh" "$PATCH_DIR")
gcc_version=$("${CROSS_COMPILE}gcc" -dumpfullversion -dumpversion)
printf '%s\n' \
    "{\"schema\":1,\"arch\":\"arm\",\"board\":\"onecloud\",\"kernel_release\":\"$KERNEL_RELEASE\",\"linux_commit\":\"$LINUX_COMMIT\",\"armbian_build_commit\":\"$ARMBIAN_BUILD_COMMIT\",\"armbian_version\":\"$ARMBIAN_VERSION\",\"armbian_config_sha256\":\"$KERNEL_CONFIG_SHA256\",\"armbian_patches_hash\":\"$ARMBIAN_PATCHES_HASH\",\"armbian_drivers_hash\":\"$ARMBIAN_DRIVERS_HASH\",\"patches_sha256\":\"$patch_digest\",\"toolchain_container\":\"$TOOLCHAIN_CONTAINER\",\"gcc\":\"$gcc_version\",\"uimage_load_address\":\"$UIMAGE_LOAD_ADDRESS\",\"uimage_entry_point\":\"$UIMAGE_ENTRY_POINT\",\"candidate_extraargs\":\"$CANDIDATE_EXTRAARGS\",\"automatic_module_loading\":false,\"hardware_boot_tested\":false,\"hardware_encoder_tested\":false}" \
  >"$OUTPUT_DIR/source-manifest.json"
(
  cd "$OUTPUT_DIR"
  sha256sum Module.symvers System.map kernel.config meson8b-onecloud.dtb \
    module-signing.json modules.tar.xz source-manifest.json uImage zImage >SHA256SUMS
)

HCODEC_KERNEL_SOURCE="$SOURCE_DIR" HCODEC_KERNEL_BUILD="$BUILD_DIR" \
  HCODEC_BASE_EVIDENCE="$EVIDENCE_DIR" HCODEC_OUTPUT_DIR="$OUTPUT_DIR" \
  "$ROOT_DIR/experimental/hcodec/scripts/verify-kernel.sh"
