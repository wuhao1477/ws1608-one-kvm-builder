#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/config/tool-versions.env"
export BASE_ID BASE_FLAVOR BASE_KERNEL BASE_BOARD BASE_RELEASE_TAG
export BASE_IMAGE_NAME BASE_IMAGE_URL BASE_IMAGE_SHA256 AMLIMG_REPOSITORY AMLIMG_COMMIT

BASE_IMAGE_XZ=${BASE_IMAGE_XZ:?BASE_IMAGE_XZ is required}
ONE_KVM_DEB=${ONE_KVM_DEB:?ONE_KVM_DEB is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
ONE_KVM_VERSION=${ONE_KVM_VERSION:?ONE_KVM_VERSION is required}
UPSTREAM_TAG=${UPSTREAM_TAG:?UPSTREAM_TAG is required}
PACKAGE_NAME=${PACKAGE_NAME:?PACKAGE_NAME is required}
PACKAGE_URL=${PACKAGE_URL:?PACKAGE_URL is required}
PACKAGE_DIGEST=${PACKAGE_DIGEST:?PACKAGE_DIGEST is required}
BUILD_TAG=${BUILD_TAG:?BUILD_TAG is required}
BUILD_NUMBER=${BUILD_NUMBER:?BUILD_NUMBER is required}
BUILD_REVISION=${BUILD_REVISION:?BUILD_REVISION is required}
BUILDER_COMMIT=${BUILDER_COMMIT:?BUILDER_COMMIT is required}
IMAGE_NAME=${IMAGE_NAME:?IMAGE_NAME is required}
GITHUB_RUN_ID=${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}
GITHUB_RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}
GITHUB_RUN_NUMBER=${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER is required}
OUTPUT_DIR=${OUTPUT_DIR:-$ROOT_DIR/out}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/.build}
export ONE_KVM_VERSION UPSTREAM_TAG PACKAGE_NAME PACKAGE_URL PACKAGE_DIGEST
export BUILD_TAG BUILD_NUMBER BUILD_REVISION BUILDER_COMMIT GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_RUN_NUMBER

BASE_IMAGE="$WORK_DIR/base.burn.img"
PACKAGE_DIR="$WORK_DIR/package"
ROOTFS_RAW="$WORK_DIR/rootfs.raw"
ROUNDTRIP_RAW="$WORK_DIR/rootfs.roundtrip.raw"
MOUNT_DIR="$WORK_DIR/rootfs.mnt"
RESOLV_BACKUP="$WORK_DIR/resolv.conf.backup"
METADATA_FILE="$WORK_DIR/ws1608-one-kvm-release"
image_identity=${BUILD_TAG#ws1608-one-kvm-}
expected_image="One-KVM_${image_identity}_${BASE_FLAVOR}.burn.img"
OUTPUT_IMAGE="$OUTPUT_DIR/$expected_image"

as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

require_command() {
  command -v "$1" >/dev/null || { echo "missing command: $1" >&2; exit 1; }
}

require_basename() {
  local value=$1 label=$2
  if [[ -z "$value" || "$value" == . || "$value" == .. || "$value" == *"/"* || "$value" == *"\\"* ]]; then
    echo "$label is not a basename: $value" >&2
    exit 1
  fi
}

require_private_dir() {
  local value=$1 label=$2 resolved
  resolved=$(realpath -m -- "$value")
  if [[ "$resolved" == / || "$resolved" == "$ROOT_DIR" || -L "$value" ]]; then
    echo "$label is not an isolated build directory: $value" >&2
    exit 1
  fi
}

assert_no_mounts_under() {
  local value target resolved
  resolved=$(realpath -m -- "$1")
  while IFS= read -r target; do
    [[ "$target" == "$resolved" || "$target" == "$resolved"/* ]] || continue
    echo "stale mount exists under build path: $target" >&2
    exit 1
  done < <(findmnt --raw --noheadings --output TARGET 2>/dev/null || true)
}

assert_rootfs_path() {
  local guest=$1 root resolved
  [[ "$guest" == /* && "$guest" != *".."* ]] || { echo "invalid rootfs path: $guest" >&2; exit 1; }
  root=$(realpath -e -- "$MOUNT_DIR")
  resolved=$(realpath -m -- "$MOUNT_DIR$guest")
  [[ "$resolved" == "$root"/* ]] || { echo "rootfs path escapes mount: $guest -> $resolved" >&2; exit 1; }
}

for command in awk chroot cmp e2fsck findmnt jq mknod mount mountpoint node realpath sha1sum umount unshare xz; do
  require_command "$command"
done
require_private_dir "$WORK_DIR" WORK_DIR
require_private_dir "$OUTPUT_DIR" OUTPUT_DIR
require_basename "$IMAGE_NAME" IMAGE_NAME
[[ "$image_identity" != "$BUILD_TAG" && "$image_identity" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "invalid build tag: $BUILD_TAG" >&2
  exit 1
}
[[ "$BUILD_TAG" == *"-$BUILD_REVISION" && "$BUILD_REVISION" =~ ^b[0-9]+$ ]] || {
  echo "build revision does not match build tag: $BUILD_REVISION" >&2
  exit 1
}
[[ "$IMAGE_NAME" == "$expected_image" ]] || {
  echo "IMAGE_NAME does not match build identity: $IMAGE_NAME" >&2
  exit 1
}
[[ -x "$AMLIMG_BIN" ]] || { echo "AmlImg binary is not executable: $AMLIMG_BIN" >&2; exit 1; }
[[ -f "$BASE_IMAGE_XZ" && ! -L "$BASE_IMAGE_XZ" ]] || { echo "invalid base image: $BASE_IMAGE_XZ" >&2; exit 1; }
[[ -f "$ONE_KVM_DEB" && ! -L "$ONE_KVM_DEB" ]] || { echo "invalid One-KVM package: $ONE_KVM_DEB" >&2; exit 1; }
[[ -x /usr/bin/qemu-arm-static ]] || { echo 'qemu-arm-static is required' >&2; exit 1; }

assert_no_mounts_under "$MOUNT_DIR"
mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
[[ ! -L "$WORK_DIR" && ! -L "$OUTPUT_DIR" ]] || { echo 'build directories must not be symlinks' >&2; exit 1; }
rm -f -- "$BASE_IMAGE" "$ROOTFS_RAW" "$ROUNDTRIP_RAW" "$RESOLV_BACKUP" "$METADATA_FILE"
rm -rf -- "$PACKAGE_DIR" "$MOUNT_DIR"

root_mounted=false
dev_mounted=false
cleanup_mounts() (
  set +e
  local failed=0
  as_root sync || failed=1
  if [[ "$dev_mounted" == true ]] && mountpoint -q "$MOUNT_DIR/dev"; then
    as_root umount "$MOUNT_DIR/dev" || failed=1
  fi
  if [[ "$root_mounted" == true ]] && mountpoint -q "$MOUNT_DIR"; then
    as_root umount "$MOUNT_DIR" || failed=1
  fi
  mountpoint -q "$MOUNT_DIR/dev" && failed=1
  mountpoint -q "$MOUNT_DIR" && failed=1
  return "$failed"
)
on_exit() { local status=$?; trap - EXIT; cleanup_mounts || true; exit "$status"; }
trap on_exit EXIT

echo 'Decompressing base image'
xz -dc "$BASE_IMAGE_XZ" > "$BASE_IMAGE"
mkdir -p "$PACKAGE_DIR"
"$AMLIMG_BIN" unpack "$BASE_IMAGE" "$PACKAGE_DIR"
rootfs_sparse=$(awk -F: '$1 == "PARTITION" && $2 == "rootfs" {print $4; exit}' "$PACKAGE_DIR/commands.txt")
rootfs_verify=$(awk -F: '$1 == "VERIFY" && $2 == "rootfs" {print $4; exit}' "$PACKAGE_DIR/commands.txt")
require_basename "$rootfs_sparse" rootfs_partition
require_basename "$rootfs_verify" rootfs_verify

node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$PACKAGE_DIR/$rootfs_sparse" "$ROOTFS_RAW"
as_root e2fsck -fn "$ROOTFS_RAW"
mkdir -p "$MOUNT_DIR"
as_root mount -o loop "$ROOTFS_RAW" "$MOUNT_DIR"
root_mounted=true
assert_rootfs_path /dev
as_root mount -t tmpfs -o mode=0755,nosuid,noexec tmpfs "$MOUNT_DIR/dev"
dev_mounted=true
for device in 'null 1 3 666' 'zero 1 5 666' 'random 1 8 666' 'urandom 1 9 666' 'tty 5 0 666'; do
  read -r name major minor mode <<<"$device"
  as_root mknod -m "$mode" "$MOUNT_DIR/dev/$name" c "$major" "$minor"
done
assert_rootfs_path /proc
as_root mkdir -p "$MOUNT_DIR/dev/pts" "$MOUNT_DIR/dev/shm" "$MOUNT_DIR/proc"
as_root rm -f "$MOUNT_DIR/dev/fd"
as_root ln -s /proc/self/fd "$MOUNT_DIR/dev/fd"

for guest in /etc /usr/bin/qemu-arm-static /tmp/one-kvm.deb /usr/local/sbin/systemctl; do
  assert_rootfs_path "$guest"
done
resolv_kind=missing
resolv_link=''
if [[ -L "$MOUNT_DIR/etc/resolv.conf" ]]; then
  resolv_kind=link
  resolv_link=$(readlink "$MOUNT_DIR/etc/resolv.conf")
elif [[ -f "$MOUNT_DIR/etc/resolv.conf" ]]; then
  resolv_kind=file
  as_root cp -a "$MOUNT_DIR/etc/resolv.conf" "$RESOLV_BACKUP"
fi
as_root rm -f "$MOUNT_DIR/etc/resolv.conf"
as_root cp -L /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf"
as_root install -D -m 0755 /usr/bin/qemu-arm-static "$MOUNT_DIR/usr/bin/qemu-arm-static"
as_root install -D -m 0644 "$ONE_KVM_DEB" "$MOUNT_DIR/tmp/one-kvm.deb"
as_root install -D -m 0755 "$ROOT_DIR/config/systemctl-build-stub" "$MOUNT_DIR/usr/local/sbin/systemctl"

read -r -d '' install_script <<'EOF' || true
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 update
apt-get -y --no-install-recommends install /tmp/one-kvm.deb
rm -f /tmp/one-kvm.deb /usr/local/sbin/systemctl /usr/bin/qemu-arm-static
rm -rf /var/lib/apt/lists/*
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sfn /lib/systemd/system/one-kvm.service /etc/systemd/system/multi-user.target.wants/one-kvm.service
EOF
echo "Installing One-KVM $ONE_KVM_VERSION in isolated mount and PID namespaces"
as_root unshare --mount --pid --fork sh -euxc '
  mount --make-rprivate /
  mount -t proc proc "$1/proc"
  chroot "$1" /usr/bin/qemu-arm-static /bin/sh -euxc "$2"
' sh "$MOUNT_DIR" "$install_script"

as_root rm -f "$MOUNT_DIR/etc/resolv.conf"
if [[ "$resolv_kind" == link ]]; then
  as_root ln -s "$resolv_link" "$MOUNT_DIR/etc/resolv.conf"
elif [[ "$resolv_kind" == file ]]; then
  as_root cp -a "$RESOLV_BACKUP" "$MOUNT_DIR/etc/resolv.conf"
fi
for guest in \
  /etc/modules-load.d/one-kvm.conf \
  /usr/sbin/one-kvm-enable-otg \
  /usr/lib/systemd/system/one-kvm-otg.service \
  /etc/systemd/system/one-kvm.service.d/otg.conf \
  /etc/ws1608-one-kvm-release; do
  assert_rootfs_path "$guest"
done
as_root install -D -m 0644 "$ROOT_DIR/config/one-kvm-modules.conf" "$MOUNT_DIR/etc/modules-load.d/one-kvm.conf"
as_root install -D -m 0755 "$ROOT_DIR/config/one-kvm-enable-otg" "$MOUNT_DIR/usr/sbin/one-kvm-enable-otg"
as_root install -D -m 0644 "$ROOT_DIR/config/one-kvm-otg.service" "$MOUNT_DIR/usr/lib/systemd/system/one-kvm-otg.service"
as_root install -D -m 0644 "$ROOT_DIR/config/one-kvm.service.d-otg.conf" "$MOUNT_DIR/etc/systemd/system/one-kvm.service.d/otg.conf"
node "$ROOT_DIR/scripts/write-image-metadata.mjs" "$METADATA_FILE"
as_root install -D -m 0644 "$METADATA_FILE" "$MOUNT_DIR/etc/ws1608-one-kvm-release"

cleanup_mounts
dev_mounted=false
root_mounted=false
trap - EXIT
assert_no_mounts_under "$MOUNT_DIR"
as_root e2fsck -fy "$ROOTFS_RAW"
rm -f "$PACKAGE_DIR/$rootfs_sparse"
node "$ROOT_DIR/scripts/raw-to-sparse.mjs" "$ROOTFS_RAW" "$PACKAGE_DIR/$rootfs_sparse"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$PACKAGE_DIR/$rootfs_sparse" "$ROUNDTRIP_RAW"
cmp "$ROOTFS_RAW" "$ROUNDTRIP_RAW"
rm -f "$ROUNDTRIP_RAW"
rootfs_sha1=$(sha1sum "$PACKAGE_DIR/$rootfs_sparse" | awk '{print $1}')
printf 'sha1sum %s' "$rootfs_sha1" > "$PACKAGE_DIR/$rootfs_verify"

rm -f "$OUTPUT_IMAGE"
"$AMLIMG_BIN" pack "$OUTPUT_IMAGE" "$PACKAGE_DIR"
node "$ROOT_DIR/scripts/write-image-manifest.mjs" "$OUTPUT_DIR/manifest.json" "$OUTPUT_IMAGE"
rm -f "$ROOTFS_RAW" "$METADATA_FILE"
rm -rf "$PACKAGE_DIR" "$MOUNT_DIR"
echo "Built $OUTPUT_IMAGE"
