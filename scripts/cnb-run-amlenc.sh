#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/scripts/cnb-ci-env.sh"
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/experimental/amlenc/config/sources.env"
ensure_go

BUILD_NUMBER=${BUILD_NUMBER:-run-${GITHUB_RUN_NUMBER}-${GITHUB_RUN_ATTEMPT}}
export BUILD_NUMBER
export AMLENC_BUILD_REVISION="$BUILD_NUMBER"
export AMLENC_WORK_DIR="$ROOT_DIR/.build/amlenc"
export AMLENC_OUTPUT_DIR="$ROOT_DIR/out/amlenc"
export OUTPUT_DIR="$ROOT_DIR/out/amlenc/burn"
export WORK_DIR="$ROOT_DIR/.build/amlenc/burn"
export AMLIMG_BIN="$ROOT_DIR/.tools/AmlImg"

node "$ROOT_DIR/experimental/amlenc/scripts/verify-source-locks.mjs" \
  "$ROOT_DIR/experimental/amlenc/config/sources.env"
bash "$ROOT_DIR/experimental/amlenc/scripts/verify-stable-chain.sh"

apt-get update
apt-get install -y curl jq qemu-user-static device-tree-compiler dpkg-dev \
  gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf build-essential \
  e2fsprogs file mtools u-boot-tools xz-utils
docker version
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --default-toolchain "$ONE_KVM_RUST_TOOLCHAIN"
source "$HOME/.cargo/env"
rustup default "$ONE_KVM_RUST_TOOLCHAIN"
cargo install cross --locked
"$ROOT_DIR/scripts/build-tools.sh" >/dev/null

docker run --rm --platform linux/amd64 \
  -v "$ROOT_DIR:/repo" -w /repo ubuntu:18.04 bash -lc '
    set -euo pipefail
    apt-get update
    apt-get install -y bc curl file git lzop make gcc-7 g++-7 \
      gcc-7-arm-linux-gnueabihf g++-7-arm-linux-gnueabihf \
      binutils-arm-linux-gnueabihf device-tree-compiler jq xz-utils
    ln -sf "$(command -v gcc-7)" /usr/local/bin/gcc
    ln -sf "$(command -v g++-7)" /usr/local/bin/g++
    ln -sf "$(command -v arm-linux-gnueabihf-gcc-7)" /usr/local/bin/arm-linux-gnueabihf-gcc
    curl --fail --location https://nodejs.org/dist/v16.20.2/node-v16.20.2-linux-x64.tar.xz \
      | tar -xJ -C /usr/local --strip-components=1
    CROSS_COMPILE=arm-linux-gnueabihf- /repo/experimental/amlenc/scripts/build-kernel.sh
  '
chown -R "$(id -u):$(id -g)" "$ROOT_DIR/.build/amlenc" "$ROOT_DIR/out/amlenc" 2>/dev/null || true
AMLENC_OUTPUT_DIR="$ROOT_DIR/out/amlenc/kernel" \
  "$ROOT_DIR/experimental/amlenc/scripts/verify-build.sh" kernel

docker run --rm --platform linux/amd64 \
  -v "$ROOT_DIR:/repo" -w /repo ubuntu:18.04 bash -lc '
    set -euo pipefail
    apt-get update
    apt-get install -y bc curl file git lzop make qemu-user-static \
      gcc-7 g++-7 gcc-7-arm-linux-gnueabihf g++-7-arm-linux-gnueabihf \
      binutils-arm-linux-gnueabihf jq xz-utils
    ln -sf "$(command -v gcc-7)" /usr/local/bin/gcc
    ln -sf "$(command -v g++-7)" /usr/local/bin/g++
    ln -sf "$(command -v arm-linux-gnueabihf-gcc-7)" /usr/local/bin/arm-linux-gnueabihf-gcc
    curl --fail --location https://nodejs.org/dist/v16.20.2/node-v16.20.2-linux-x64.tar.xz \
      | tar -xJ -C /usr/local --strip-components=1
    CC=arm-linux-gnueabihf-gcc-7 CXX=arm-linux-gnueabihf-g++-7 \
      AR=arm-linux-gnueabihf-ar READELF=arm-linux-gnueabihf-readelf \
      /repo/experimental/amlenc/scripts/build-libvpcodec.sh
  '
chown -R "$(id -u):$(id -g)" "$ROOT_DIR/.build/amlenc" "$ROOT_DIR/out/amlenc" 2>/dev/null || true
AMLENC_OUTPUT_DIR="$ROOT_DIR/out/amlenc/libvpcodec" \
  CC=arm-linux-gnueabihf-gcc "$ROOT_DIR/experimental/amlenc/scripts/verify-build.sh" libvpcodec

export DOCKER_BUILDKIT=1
export AMLENC_CROSS_IMAGE="ws1608-one-kvm-armv7:${CNB_BUILD_ID}-${CNB_BUILD_ATTEMPT}"
"$ROOT_DIR/experimental/amlenc/scripts/build-one-kvm.sh"
package=$(find "$ROOT_DIR/out/amlenc/one-kvm" -maxdepth 1 -type f -name 'one-kvm_*_armhf.deb' -print -quit)
"$ROOT_DIR/experimental/amlenc/scripts/verify-one-kvm.sh" "$package"

umask 077
key_file="$ROOT_DIR/.build/amlenc/cnb-build-key"
mkdir -p "$ROOT_DIR/.build/amlenc"
ssh-keygen -q -t ed25519 -N '' -f "$key_file"
AMLENC_SSH_PUBLIC_KEY="$(<"$key_file.pub")" \
  AMLENC_ONE_KVM_DEB="$package" \
  "$ROOT_DIR/experimental/amlenc/scripts/build-diagnostic-image.sh" --build

source "$ROOT_DIR/config/base.env"
curl --fail --silent --show-error --location --retry 5 "$BASE_IMAGE_URL" \
  -o "$ROOT_DIR/.build/amlenc/base.burn.img.xz"
printf '%s  %s\n' "$BASE_IMAGE_SHA256" "$ROOT_DIR/.build/amlenc/base.burn.img.xz" \
  | sha256sum --check
xz -dc "$ROOT_DIR/.build/amlenc/base.burn.img.xz" >"$ROOT_DIR/.build/amlenc/base.burn.img"
BASE_IMAGE_XZ="$ROOT_DIR/.build/amlenc/base.burn.img.xz" \
  DIAGNOSTIC_IMAGE="$ROOT_DIR/out/amlenc/diagnostic-image/WS1608-AMLENC-Diagnostic_k3.10.107_bullseye_${BUILD_NUMBER}.usb.img" \
  DIAGNOSTIC_MANIFEST="$ROOT_DIR/out/amlenc/diagnostic-image/manifest.json" \
  AMLIMG_BIN="$ROOT_DIR/.tools/AmlImg" OUTPUT_DIR="$ROOT_DIR/out/amlenc/burn" \
  WORK_DIR="$ROOT_DIR/.build/amlenc/burn" \
  BUILD_REVISION="$BUILD_NUMBER" \
  IMAGE_NAME="WS1608-AMLENC_0.2.6+ws1608amlenc.${BUILD_NUMBER}_Onecloud_bullseye_3.10.107.burn.img" \
  "$ROOT_DIR/experimental/amlenc/scripts/build-burn-image.sh"

export IMAGE_NAME="WS1608-AMLENC_0.2.6+ws1608amlenc.${BUILD_NUMBER}_Onecloud_bullseye_3.10.107.burn.img"
BASE_IMAGE="$ROOT_DIR/.build/amlenc/base.burn.img" \
  IMAGE="$ROOT_DIR/out/amlenc/burn/$IMAGE_NAME" \
  MANIFEST="$ROOT_DIR/out/amlenc/burn/manifest.json" \
  AMLIMG_BIN="$ROOT_DIR/.tools/AmlImg" VERIFY_DIR="$ROOT_DIR/.build/amlenc/burn-verify" \
  "$ROOT_DIR/experimental/amlenc/scripts/verify-burn-image.sh"
OUTPUT_DIR="$ROOT_DIR/out/amlenc/burn" IMAGE_NAME="$IMAGE_NAME" \
  "$ROOT_DIR/experimental/amlenc/scripts/package-burn-release.sh"
"$ROOT_DIR/experimental/amlenc/scripts/verify-stable-chain.sh"
"$ROOT_DIR/experimental/amlenc/scripts/verify-burn-release.sh" "$ROOT_DIR/out/amlenc/burn"
jq -e '.hardware_encoder_tested == false and .hardware_boot_tested == false and .one_kvm_included == true and .stable_channel_modified == false' \
  "$ROOT_DIR/out/amlenc/burn/manifest.json" >/dev/null

CNB_ASSET_TTL=14 "$ROOT_DIR/scripts/cnb-upload-commit-assets.sh" "$ROOT_DIR/out/amlenc/burn"
if [[ "${PUBLISH:-false}" == true && "${ACKNOWLEDGE_EXPERIMENTAL:-false}" == true ]]; then
  release_tag="ws1608-amlenc-exp-0.2.6-v260802-k3.10.107-b$(printf '%06d' "$((GITHUB_RUN_NUMBER * 1000 + GITHUB_RUN_ATTEMPT))")"
  notes="$ROOT_DIR/.build/amlenc/release-notes.md"
  cat >"$notes" <<EOF
Experimental WS1608/S805 image with One-KVM Rust 0.2.6 and the Meson8b AMLENC H.264 integration.

Hosted build and image validation passed. Physical flashing, boot, and hardware encoding were not tested for this build.
EOF
  RELEASE_TAG="$release_tag" RELEASE_NAME="WS1608 AMLENC experimental $BUILD_NUMBER" \
    RELEASE_COMMIT="$CNB_COMMIT" RELEASE_NOTES_FILE="$notes" \
    RELEASE_ASSET_DIR="$ROOT_DIR/out/amlenc/burn" RELEASE_PRERELEASE=true \
    RELEASE_LATEST=false "$ROOT_DIR/scripts/cnb-publish-release.sh"
fi
