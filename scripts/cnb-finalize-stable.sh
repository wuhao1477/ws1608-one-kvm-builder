#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/scripts/cnb-ci-env.sh"
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/config/tool-versions.env"

CONTEXT_FILE=${1:?usage: cnb-finalize-stable.sh CONTEXT_FILE DOWNLOAD_DIR}
source "$CONTEXT_FILE"
if [[ "${3:-}" == local ]]; then
  OUTPUT_DIR=${OUTPUT_DIR:?OUTPUT_DIR is required in stable context}
else
  OUTPUT_DIR=${2:?usage: cnb-finalize-stable.sh CONTEXT_FILE DOWNLOAD_DIR}
fi
[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || { echo 'invalid downloaded stable artifact directory' >&2; exit 1; }
export OUTPUT_DIR IMAGE_NAME VALIDATION_REPORT_NAME
export ONE_KVM_VERSION UPSTREAM_TAG PACKAGE_NAME PACKAGE_URL PACKAGE_DIGEST
export BUILD_TAG BUILD_NUMBER BUILD_REVISION BUILDER_COMMIT
export GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_RUN_NUMBER

"$ROOT_DIR/scripts/verify-release-assets.sh"

container_path() {
  local path=$1
  printf '/workspace/%s\n' "${path#"$ROOT_DIR"/}"
}

downloaded_image="$OUTPUT_DIR/$IMAGE_NAME"
base_image="$WORK_DIR/base.burn.img"
docker_env=(
  -e "BASE_ID=$BASE_ID"
  -e "BASE_FLAVOR=$BASE_FLAVOR"
  -e "BASE_KERNEL=$BASE_KERNEL"
  -e "BASE_BOARD=$BASE_BOARD"
  -e "BASE_RELEASE_TAG=$BASE_RELEASE_TAG"
  -e "BASE_IMAGE_NAME=$BASE_IMAGE_NAME"
  -e "BASE_IMAGE_URL=$BASE_IMAGE_URL"
  -e "BASE_IMAGE_SHA256=$BASE_IMAGE_SHA256"
  -e "AMLIMG_REPOSITORY=$AMLIMG_REPOSITORY"
  -e "AMLIMG_COMMIT=$AMLIMG_COMMIT"
  -e "ONE_KVM_VERSION=$ONE_KVM_VERSION"
  -e "UPSTREAM_TAG=$UPSTREAM_TAG"
  -e "PACKAGE_NAME=$PACKAGE_NAME"
  -e "PACKAGE_URL=$PACKAGE_URL"
  -e "PACKAGE_DIGEST=$PACKAGE_DIGEST"
  -e "BUILD_TAG=$BUILD_TAG"
  -e "BUILD_NUMBER=$BUILD_NUMBER"
  -e "BUILD_REVISION=$BUILD_REVISION"
  -e "BUILDER_COMMIT=$BUILDER_COMMIT"
  -e "GITHUB_RUN_ID=$GITHUB_RUN_ID"
  -e "GITHUB_RUN_ATTEMPT=$GITHUB_RUN_ATTEMPT"
  -e "GITHUB_RUN_NUMBER=$GITHUB_RUN_NUMBER"
  -e "OUTPUT_DIR=$(container_path "$OUTPUT_DIR")"
  -e "WORK_DIR=$(container_path "$WORK_DIR")"
  -e "AMLIMG_BIN=$(container_path "$AMLIMG_BIN")"
  -e "IMAGE_NAME=$IMAGE_NAME"
  -e "VALIDATION_REPORT_NAME=$VALIDATION_REPORT_NAME"
  -e "IMAGE=$(container_path "$downloaded_image")"
  -e "BASE_IMAGE=$(container_path "$base_image")"
  -e "VERIFY_DIR=$(container_path "$WORK_DIR/download-verify")"
  -e "VALIDATION_REPORT=$(container_path "$WORK_DIR/download-validation-report.json")"
  -e "CNB_FUSE_ROOTFS=true"
)

docker run --rm --privileged --cap-add=SYS_ADMIN \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined --pid=host --volume /sys:/sys:ro \
  --device /dev/loop-control --device /dev/fuse --device-cgroup-rule='b 7:* rmw' \
  --platform linux/amd64 -v "$ROOT_DIR:/workspace" -w /workspace \
  "${docker_env[@]}" node:22-bookworm bash -lc '
    set -Eeuo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y binutils e2fsprogs file fuse2fs fuse3 jq mtools qemu-user-static util-linux xz-utils
    for loop_minor in 0 1 2 3 4 5 6 7; do
      mknod -m 660 "/dev/loop$loop_minor" b 7 "$loop_minor" 2>/dev/null || :
    done
    /workspace/scripts/verify-image.sh
  '

if [[ "$PUBLISH" == true ]]; then
  RELEASE_TAG="$BUILD_TAG" RELEASE_NAME="WS1608 One-KVM Rust $ONE_KVM_VERSION ($UPSTREAM_TAG, $BUILD_REVISION)" \
    RELEASE_COMMIT="$BUILDER_COMMIT" RELEASE_NOTES_FILE="$RELEASE_NOTES_FILE" \
    RELEASE_ASSET_DIR="$OUTPUT_DIR" RELEASE_PRERELEASE="$RELEASE_PRERELEASE" \
    RELEASE_LATEST="$([[ "$RELEASE_PRERELEASE" == false ]] && printf true || printf false)" \
    "$ROOT_DIR/scripts/cnb-publish-release.sh"
fi
