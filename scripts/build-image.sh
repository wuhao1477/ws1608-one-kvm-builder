#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASE_IMAGE_XZ=${BASE_IMAGE_XZ:?BASE_IMAGE_XZ is required}
ONE_KVM_DEB=${ONE_KVM_DEB:?ONE_KVM_DEB is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
ONE_KVM_VERSION=${ONE_KVM_VERSION:?ONE_KVM_VERSION is required}
UPSTREAM_TAG=${UPSTREAM_TAG:?UPSTREAM_TAG is required}
OUTPUT_DIR=${OUTPUT_DIR:-$ROOT_DIR/out}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/.build}

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
BASE_IMAGE="$WORK_DIR/base.burn.img"
PACKAGE_DIR="$WORK_DIR/package"
ROOTFS_RAW="$WORK_DIR/rootfs.raw"
MOUNT_DIR="$WORK_DIR/rootfs.mnt"
OUTPUT_IMAGE="$OUTPUT_DIR/One-KVM_${ONE_KVM_VERSION}_Onecloud_trixie_6.12.28_HDMI-test.burn.img"

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

cleanup_mounts() {
  set +e
  if mountpoint -q "$MOUNT_DIR/etc/resolv.conf"; then as_root umount "$MOUNT_DIR/etc/resolv.conf"; fi
  if mountpoint -q "$MOUNT_DIR/proc"; then as_root umount "$MOUNT_DIR/proc"; fi
  if mountpoint -q "$MOUNT_DIR/sys"; then as_root umount -R "$MOUNT_DIR/sys"; fi
  if mountpoint -q "$MOUNT_DIR/dev"; then as_root umount -R "$MOUNT_DIR/dev"; fi
  if mountpoint -q "$MOUNT_DIR"; then as_root umount "$MOUNT_DIR"; fi
}
trap cleanup_mounts EXIT

mkdir -p "$MOUNT_DIR"
as_root mount -o loop "$ROOTFS_RAW" "$MOUNT_DIR"
as_root mount --rbind /dev "$MOUNT_DIR/dev"
as_root mount --make-rslave "$MOUNT_DIR/dev"
as_root mount -t proc proc "$MOUNT_DIR/proc"
as_root mount -t sysfs sysfs "$MOUNT_DIR/sys"

resolv_link=''
if [[ -L "$MOUNT_DIR/etc/resolv.conf" ]]; then
  resolv_link=$(readlink "$MOUNT_DIR/etc/resolv.conf")
fi
as_root rm -f "$MOUNT_DIR/etc/resolv.conf"
as_root cp -L /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf"
as_root mount --bind /etc/resolv.conf "$MOUNT_DIR/etc/resolv.conf"

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

if [[ -n "$resolv_link" ]]; then
  as_root umount "$MOUNT_DIR/etc/resolv.conf"
  as_root rm -f "$MOUNT_DIR/etc/resolv.conf"
  as_root ln -s "$resolv_link" "$MOUNT_DIR/etc/resolv.conf"
else
  as_root umount "$MOUNT_DIR/etc/resolv.conf"
fi

echo "Installing WS1608 OTG integration"
as_root install -D -m 0644 "$ROOT_DIR/config/one-kvm-modules.conf" "$MOUNT_DIR/etc/modules-load.d/one-kvm.conf"
as_root install -D -m 0755 "$ROOT_DIR/config/one-kvm-enable-otg" "$MOUNT_DIR/usr/sbin/one-kvm-enable-otg"
as_root install -D -m 0644 "$ROOT_DIR/config/one-kvm-otg.service" "$MOUNT_DIR/etc/systemd/system/one-kvm-otg.service"
as_root install -D -m 0644 "$ROOT_DIR/config/one-kvm.service.d-otg.conf" "$MOUNT_DIR/etc/systemd/system/one-kvm.service.d/otg.conf"

as_root tee "$MOUNT_DIR/etc/ws1608-one-kvm-release" >/dev/null <<EOF
one_kvm_version=$ONE_KVM_VERSION
one_kvm_release=$UPSTREAM_TAG
base=Armbian_26.8.0-trunk.413_Onecloud_trixie_6.12.28_HDMI-test
kernel=6.12.28-current-meson
board=ws1608
EOF
as_root chown root:root "$MOUNT_DIR/etc/ws1608-one-kvm-release"

cleanup_mounts
trap - EXIT
as_root e2fsck -fy "$ROOTFS_RAW"
rm -f "$PACKAGE_DIR/$rootfs_sparse"
echo "Creating Android sparse rootfs"
node "$ROOT_DIR/scripts/raw-to-sparse.mjs" "$ROOTFS_RAW" "$PACKAGE_DIR/$rootfs_sparse"
rootfs_sha1=$(sha1sum "$PACKAGE_DIR/$rootfs_sparse" | awk '{print $1}')
printf 'sha1sum %s' "$rootfs_sha1" > "$PACKAGE_DIR/$rootfs_verify"

echo "Repacking Amlogic container"
rm -f "$OUTPUT_IMAGE"
"$AMLIMG_BIN" pack "$OUTPUT_IMAGE" "$PACKAGE_DIR"
sha256sum "$OUTPUT_IMAGE" > "$OUTPUT_IMAGE.sha256"
cat > "$OUTPUT_DIR/manifest.json" <<EOF
{
  "board": "WS1608 / OneCloud",
  "base": "Armbian_26.8.0-trunk.413_Onecloud_trixie_6.12.28_HDMI-test",
  "kernel": "6.12.28-current-meson",
  "one_kvm_version": "$ONE_KVM_VERSION",
  "one_kvm_release": "$UPSTREAM_TAG",
  "image": "$(basename "$OUTPUT_IMAGE")",
  "image_sha256": "$(cut -d' ' -f1 "$OUTPUT_IMAGE.sha256")"
}
EOF
rm -f "$ROOTFS_RAW"
rm -rf "$PACKAGE_DIR"
echo "Built $OUTPUT_IMAGE"
