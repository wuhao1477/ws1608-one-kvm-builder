#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/scripts/cnb-ci-env.sh"
source "$ROOT_DIR/config/base.env"
ensure_go

ARMBIAN_IMAGE=${ARMBIAN_IMAGE:-ubuntu:24.04@sha256:1e0a86e57d247923571b75e0aaf48a1449cf8c543d51fb3e07a4a7d7bfa79316}
export BASE_RELEASE_TAG BASE_IMAGE_SHA256
export BASE_IMAGE_XZ="$ROOT_DIR/.build/hcodec/base.burn.img.xz"
export HCODEC_BASE_EVIDENCE="$ROOT_DIR/.build/hcodec/base-evidence"
mkdir -p "$ROOT_DIR/out/hcodec/kernel" "$ROOT_DIR/out/hcodec/tools" \
  "$ROOT_DIR/out/hcodec/firmware" "$ROOT_DIR/out/hcodec/artifact"

curl --fail --silent --show-error --location --retry 5 "$BASE_IMAGE_URL" -o "$BASE_IMAGE_XZ"
printf '%s  %s\n' "$BASE_IMAGE_SHA256" "$BASE_IMAGE_XZ" | sha256sum --check
"$ROOT_DIR/experimental/hcodec/scripts/collect-base-evidence.sh" collect "$HCODEC_BASE_EVIDENCE"

docker run --rm --platform linux/amd64 --privileged \
  -e ALLOW_ROOT=yes -e PRE_PREPARED_HOST=yes -e ARMBIAN_INSIDE_DOCKERFILE_BUILD=yes \
  -e SKIP_LOG_ARCHIVE=yes -e KERNEL_CONFIGURE=no -e SHARE_LOG=no \
  -e HCODEC_BASE_EVIDENCE=/repo/.build/hcodec/base-evidence \
  -v "$ROOT_DIR:/repo" -w /repo "$ARMBIAN_IMAGE" bash -lc '
    set -Eeuo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y bc bison build-essential flex git kmod libssl-dev lzop rsync \
      u-boot-tools xz-utils curl device-tree-compiler gcc-arm-linux-gnueabihf \
      binutils-arm-linux-gnueabihf nodejs
    /repo/experimental/hcodec/scripts/build-kernel.sh
  '

"$ROOT_DIR/experimental/hcodec/scripts/build-tools.sh" "$ROOT_DIR/out/hcodec/tools"
"$ROOT_DIR/experimental/hcodec/scripts/build-firmware.sh" "$ROOT_DIR/out/hcodec/firmware"
"$ROOT_DIR/experimental/hcodec/scripts/package-artifact.sh" \
  "$ROOT_DIR/out/hcodec/kernel" "$ROOT_DIR/out/hcodec/tools" \
  "$ROOT_DIR/out/hcodec/firmware" "$ROOT_DIR/out/hcodec/artifact" \
  "$GITHUB_RUN_NUMBER" "$GITHUB_RUN_ATTEMPT"
"$ROOT_DIR/experimental/hcodec/scripts/verify-artifact.sh" "$ROOT_DIR/out/hcodec/artifact"
