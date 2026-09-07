#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/scripts/cnb-ci-env.sh"
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/config/tool-versions.env"
ensure_go

apt-get update
apt-get install -y binutils e2fsprogs file jq mtools qemu-user-static util-linux xz-utils

FORCE_BUILD=${FORCE_BUILD:-false}
PUBLISH=${PUBLISH:-true}
RELEASE_PRERELEASE=${RELEASE_PRERELEASE:-false}
discovery=$(mktemp)
trap 'rm -f "$discovery"' EXIT
FORCE_BUILD="$FORCE_BUILD" "$ROOT_DIR/scripts/cnb-discover-release.sh" >"$discovery"
source "$discovery"
[[ "$changed" == true ]] || { echo "no new One-KVM input for $release_tag"; exit 0; }

UPSTREAM_TAG=${UPSTREAM_TAG:-$release_tag}
BUILD_TAG=${BUILD_TAG:-$build_tag}
BUILD_NUMBER=${BUILD_NUMBER:-$build_number}
BUILD_REVISION=${BUILD_REVISION:-$build_revision}
IMAGE_STEM=${IMAGE_STEM:-$image_stem}
ONE_KVM_VERSION=${ONE_KVM_VERSION:-$one_kvm_version}
PACKAGE_NAME=${PACKAGE_NAME:-$package_name}
PACKAGE_URL=${PACKAGE_URL:-$package_url}
PACKAGE_DIGEST=${PACKAGE_DIGEST:-$package_digest}
BUILDER_COMMIT=${BUILDER_COMMIT:-$CNB_COMMIT}

export BASE_ID BASE_FLAVOR BASE_KERNEL BASE_BOARD BASE_RELEASE_TAG
export BASE_IMAGE_NAME BASE_IMAGE_URL BASE_IMAGE_SHA256 AMLIMG_REPOSITORY AMLIMG_COMMIT
export ONE_KVM_VERSION UPSTREAM_TAG PACKAGE_NAME PACKAGE_URL PACKAGE_DIGEST
export BUILD_TAG BUILD_NUMBER BUILD_REVISION BUILDER_COMMIT
export GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_RUN_NUMBER
export OUTPUT_DIR="$ROOT_DIR/out/cnb-stable/$BUILD_TAG"
export WORK_DIR="$ROOT_DIR/.build/cnb-stable/$BUILD_TAG"
export VALIDATION_REPORT="$OUTPUT_DIR/validation-report.json"
export VALIDATION_REPORT_NAME=validation-report.json
export IMAGE_NAME="One-KVM_${IMAGE_STEM}_${BASE_FLAVOR}.burn.img"
export GITHUB_OUTPUT=/dev/null

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
export TOOLS_DIR="$WORK_DIR/tools"
export AMLIMG_BIN
AMLIMG_BIN=$(TOOLS_DIR="$TOOLS_DIR" "$ROOT_DIR/scripts/build-tools.sh")

curl --fail --silent --show-error --location --retry 5 "$BASE_IMAGE_URL" \
  -o "$WORK_DIR/$BASE_IMAGE_NAME"
printf '%s  %s\n' "$BASE_IMAGE_SHA256" "$WORK_DIR/$BASE_IMAGE_NAME" | sha256sum --check
export BASE_IMAGE_XZ="$WORK_DIR/$BASE_IMAGE_NAME"
curl --fail --silent --show-error --location --retry 5 "$PACKAGE_URL" \
  -o "$WORK_DIR/$PACKAGE_NAME"
printf '%s  %s\n' "$PACKAGE_DIGEST" "$WORK_DIR/$PACKAGE_NAME" | sha256sum --check
dpkg-deb -f "$WORK_DIR/$PACKAGE_NAME" Package | grep -Fx one-kvm >/dev/null
dpkg-deb -f "$WORK_DIR/$PACKAGE_NAME" Version | grep -Fx "$ONE_KVM_VERSION" >/dev/null
dpkg-deb -f "$WORK_DIR/$PACKAGE_NAME" Architecture | grep -Fx armhf >/dev/null
export ONE_KVM_DEB="$WORK_DIR/$PACKAGE_NAME"

container_path() {
  local path=$1
  printf '/workspace/%s\n' "${path#"$ROOT_DIR"/}"
}

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
  -e "BASE_IMAGE_XZ=$(container_path "$BASE_IMAGE_XZ")"
  -e "ONE_KVM_DEB=$(container_path "$ONE_KVM_DEB")"
  -e "AMLIMG_BIN=$(container_path "$AMLIMG_BIN")"
  -e "VALIDATION_REPORT=$(container_path "$VALIDATION_REPORT")"
  -e "IMAGE_NAME=$IMAGE_NAME"
  -e "VALIDATION_REPORT_NAME=$VALIDATION_REPORT_NAME"
)

docker run --rm --privileged --cap-add=SYS_ADMIN \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined --pid=host --volume /sys:/sys:ro \
  --device /dev/loop-control --platform linux/amd64 \
  -v "$ROOT_DIR:/workspace" -w /workspace \
  "${docker_env[@]}" node:22-bookworm bash -lc '
    set -Eeuo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y binutils e2fsprogs file jq mtools qemu-user-static util-linux xz-utils
    /workspace/scripts/cnb-run-stable-inner.sh
  '

cat >"$WORK_DIR/release-notes.md" <<EOF
## WS1608 One-KVM Rust $ONE_KVM_VERSION

Upstream One-KVM release: [$UPSTREAM_TAG](https://github.com/mofeng-git/One-KVM/releases/tag/$UPSTREAM_TAG)

Build: $BUILD_REVISION. Base: Armbian $BASE_RELEASE_TAG, kernel $BASE_KERNEL, $BASE_FLAVOR.

Built and published by CNB. Hosted validation cannot flash a physical WS1608; this is not a hardware boot result.
EOF

if [[ "$PUBLISH" == true ]]; then
  RELEASE_TAG="$BUILD_TAG" RELEASE_NAME="WS1608 One-KVM Rust $ONE_KVM_VERSION ($UPSTREAM_TAG, $BUILD_REVISION)" \
    RELEASE_COMMIT="$BUILDER_COMMIT" RELEASE_NOTES_FILE="$WORK_DIR/release-notes.md" \
    RELEASE_ASSET_DIR="$OUTPUT_DIR" RELEASE_PRERELEASE="$RELEASE_PRERELEASE" \
    RELEASE_LATEST="$([[ "$RELEASE_PRERELEASE" == false ]] && printf true || printf false)" \
    "$ROOT_DIR/scripts/cnb-publish-release.sh"
else
  CNB_ASSET_TTL=14 "$ROOT_DIR/scripts/cnb-upload-commit-assets.sh" "$OUTPUT_DIR"
fi
