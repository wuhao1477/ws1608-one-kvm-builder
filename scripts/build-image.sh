#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/config/base.env"
BASE_IMAGE_XZ=${BASE_IMAGE_XZ:?BASE_IMAGE_XZ is required}
ONE_KVM_DEB=${ONE_KVM_DEB:?ONE_KVM_DEB is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
ONE_KVM_VERSION=${ONE_KVM_VERSION:?ONE_KVM_VERSION is required}
UPSTREAM_TAG=${UPSTREAM_TAG:?UPSTREAM_TAG is required}
BUILD_TAG=${BUILD_TAG:?BUILD_TAG is required}
BUILD_NUMBER=${BUILD_NUMBER:?BUILD_NUMBER is required}
PACKAGE_DIGEST=${PACKAGE_DIGEST:?PACKAGE_DIGEST is required}
BUILDER_COMMIT=${BUILDER_COMMIT:?BUILDER_COMMIT is required}
OUTPUT_DIR=${OUTPUT_DIR:-$ROOT_DIR/out}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/.build}

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
BASE_IMAGE="$WORK_DIR/base.burn.img"
PACKAGE_DIR="$WORK_DIR/package"
ROOTFS_RAW="$WORK_DIR/rootfs.raw"
ROUNDTRIP_RAW="$WORK_DIR/rootfs.roundtrip.raw"
MOUNT_DIR="$WORK_DIR/rootfs.mnt"
RESOLV_BACKUP="$WORK_DIR/resolv.conf.backup"
METADATA_FILE="$WORK_DIR/ws1608-one-kvm-release"
image_identity=${BUILD_TAG#ws1608-one-kvm-}
[[ "$image_identity" != "$BUILD_TAG" ]] || { echo "invalid build tag: $BUILD_TAG" >&2; exit 1; }
OUTPUT_IMAGE="$OUTPUT_DIR/One-KVM_${image_identity}_${BASE_FLAVOR}.burn.img"

as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

require_command() {
  command -v "$1" >/dev/null || { echo "missing command: $1" >&2; exit 1; }
}

for command in xz node sha1sum sha256sum e2fsck mount umount mountpoint chroot; do
  require_command "$command"
done
[[ -x "$AMLIMG_BIN" ]] || { echo "AmlImg binary is not executable: $AMLIMG_BIN" >&2; exit 1; }
[[ -f "$BASE_IMAGE_XZ" ]] || { echo "base image not found: $BASE_IMAGE_XZ" >&2; exit 1; }
[[ -f "$ONE_KVM_DEB" ]] || { echo "One-KVM package not found: $ONE_KVM_DEB" >&2; exit 1; }
[[ -x /usr/bin/qemu-arm-static ]] || {
  echo 'qemu-arm-static is required to configure the armhf rootfs' >&2
  exit 1
}

echo "Decompressing base image"
xz -dc "$BASE_IMAGE_XZ" > "$BASE_IMAGE"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
echo "Unpacking Amlogic container"
"$AMLIMG_BIN" unpack "$BASE_IMAGE" "$PACKAGE_DIR"

rootfs_sparse=$(awk -F: '$1 == "PARTITION" && $2 == "rootfs" {print $4; exit}' "$PACKAGE_DIR/commands.txt")
rootfs_verify=$(awk -F: '$1 == "VERIFY" && $2 == "rootfs" {print $4; exit}' "$PACKAGE_DIR/commands.txt")
[[ -n "$rootfs_sparse" && -n "$rootfs_verify" ]] || {
  echo 'base image has no rootfs partition and VERIFY entry' >&2
  exit 1
}

echo "Expanding rootfs sparse image"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$PACKAGE_DIR/$rootfs_sparse" "$ROOTFS_RAW"
as_root e2fsck -fn "$ROOTFS_RAW"

cleanup_mounts() (
  set -u
  local failed=0
  as_root sync || failed=1
  for target in "$MOUNT_DIR/proc" "$MOUNT_DIR/sys" "$MOUNT_DIR/dev"; do
    if mountpoint -q "$target" && ! as_root umount "$target"; then failed=1; fi
  done
  if mountpoint -q "$MOUNT_DIR" && ! as_root umount "$MOUNT_DIR"; then failed=1; fi
  if mountpoint -q "$MOUNT_DIR"; then
    echo "rootfs mount is still active: $MOUNT_DIR" >&2
    failed=1
  fi
  return "$failed"
)
on_exit() { cleanup_mounts || true; }
trap on_exit EXIT

mkdir -p "$MOUNT_DIR"
as_root mount -o loop "$ROOTFS_RAW" "$MOUNT_DIR"
as_root mount --bind /dev "$MOUNT_DIR/dev"
as_root mount -t proc proc "$MOUNT_DIR/proc"
as_root mount -t sysfs sysfs "$MOUNT_DIR/sys"

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

echo "Installing One-KVM $ONE_KVM_VERSION in armhf rootfs"
as_root chroot "$MOUNT_DIR" /usr/bin/qemu-arm-static /bin/sh -euxc '
  export DEBIAN_FRONTEND=noninteractive
  apt-get -o Acquire::Retries=3 update
  apt-get -y --no-install-recommends install /tmp/one-kvm.deb
  rm -f /tmp/one-kvm.deb /usr/local/sbin/systemctl /usr/bin/qemu-arm-static
  rm -rf /var/lib/apt/lists/*
  mkdir -p /etc/systemd/system/multi-user.target.wants
  ln -sfn /lib/systemd/system/one-kvm.service /etc/systemd/system/multi-user.target.wants/one-kvm.service
'

as_root rm -f "$MOUNT_DIR/etc/resolv.conf"
if [[ "$resolv_kind" == link ]]; then
  as_root ln -s "$resolv_link" "$MOUNT_DIR/etc/resolv.conf"
elif [[ "$resolv_kind" == file ]]; then
  as_root cp -a "$RESOLV_BACKUP" "$MOUNT_DIR/etc/resolv.conf"
fi
mountpoint -q "$MOUNT_DIR" || { echo 'rootfs was unmounted unexpectedly' >&2; exit 1; }

echo "Installing WS1608 OTG integration"
as_root install -D -m 0644 "$ROOT_DIR/config/one-kvm-modules.conf" "$MOUNT_DIR/etc/modules-load.d/one-kvm.conf"
as_root install -D -m 0755 "$ROOT_DIR/config/one-kvm-enable-otg" "$MOUNT_DIR/usr/sbin/one-kvm-enable-otg"
as_root install -D -m 0644 "$ROOT_DIR/config/one-kvm-otg.service" "$MOUNT_DIR/usr/lib/systemd/system/one-kvm-otg.service"
as_root install -D -m 0644 "$ROOT_DIR/config/one-kvm.service.d-otg.conf" "$MOUNT_DIR/etc/systemd/system/one-kvm.service.d/otg.conf"
test -f "$MOUNT_DIR/usr/lib/systemd/system/one-kvm-otg.service"
test -f "$MOUNT_DIR/etc/systemd/system/one-kvm.service.d/otg.conf"

node "$ROOT_DIR/scripts/write-image-metadata.mjs" "$METADATA_FILE"
as_root install -D -m 0644 "$METADATA_FILE" "$MOUNT_DIR/etc/ws1608-one-kvm-release"

cleanup_mounts
trap - EXIT
mountpoint -q "$MOUNT_DIR" && { echo 'rootfs is still mounted before e2fsck' >&2; exit 1; }
as_root e2fsck -fy "$ROOTFS_RAW"
rm -f "$PACKAGE_DIR/$rootfs_sparse"
echo "Creating Android sparse rootfs"
node "$ROOT_DIR/scripts/raw-to-sparse.mjs" "$ROOTFS_RAW" "$PACKAGE_DIR/$rootfs_sparse"
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$PACKAGE_DIR/$rootfs_sparse" "$ROUNDTRIP_RAW"
cmp "$ROOTFS_RAW" "$ROUNDTRIP_RAW"
rm -f "$ROUNDTRIP_RAW"
rootfs_sha1=$(sha1sum "$PACKAGE_DIR/$rootfs_sparse" | awk '{print $1}')
printf 'sha1sum %s' "$rootfs_sha1" > "$PACKAGE_DIR/$rootfs_verify"

echo "Repacking Amlogic container"
rm -f "$OUTPUT_IMAGE"
"$AMLIMG_BIN" pack "$OUTPUT_IMAGE" "$PACKAGE_DIR"
node "$ROOT_DIR/scripts/write-image-manifest.mjs" "$OUTPUT_DIR/manifest.json" "$OUTPUT_IMAGE"
rm -f "$ROOTFS_RAW"
rm -f "$METADATA_FILE"
rm -rf "$PACKAGE_DIR"
echo "Built $OUTPUT_IMAGE"
