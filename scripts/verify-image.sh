#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/config/base.env"
IMAGE=${IMAGE:?IMAGE is required}
BASE_IMAGE=${BASE_IMAGE:?BASE_IMAGE is required}
AMLIMG_BIN=${AMLIMG_BIN:?AMLIMG_BIN is required}
ONE_KVM_VERSION=${ONE_KVM_VERSION:?ONE_KVM_VERSION is required}
UPSTREAM_TAG=${UPSTREAM_TAG:?UPSTREAM_TAG is required}
PACKAGE_DIGEST=${PACKAGE_DIGEST:?PACKAGE_DIGEST is required}
BUILD_TAG=${BUILD_TAG:?BUILD_TAG is required}
BUILD_NUMBER=${BUILD_NUMBER:?BUILD_NUMBER is required}
BUILDER_COMMIT=${BUILDER_COMMIT:?BUILDER_COMMIT is required}
VALIDATION_REPORT=${VALIDATION_REPORT:?VALIDATION_REPORT is required}
VERIFY_DIR=${VERIFY_DIR:-$ROOT_DIR/.verify}
FINAL_DIR="$VERIFY_DIR/final"
BASE_DIR="$VERIFY_DIR/base"
ROOTFS_RAW="$VERIFY_DIR/rootfs.raw"
MOUNT_DIR="$VERIFY_DIR/rootfs.mnt"

as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

verify() {
  local name=$1
  shift
  if "$@"; then
    echo "verified: $name"
  else
    echo "verification failed: $name" >&2
    exit 1
  fi
}

cleanup() {
  set +e
  if mountpoint -q "$MOUNT_DIR"; then as_root umount "$MOUNT_DIR"; fi
}
trap cleanup EXIT

as_root rm -rf "$VERIFY_DIR"
mkdir -p "$FINAL_DIR" "$BASE_DIR" "$MOUNT_DIR"
"$AMLIMG_BIN" unpack "$IMAGE" "$FINAL_DIR"
"$AMLIMG_BIN" unpack "$BASE_IMAGE" "$BASE_DIR"
diff -u "$ROOT_DIR/config/commands.expected" "$FINAL_DIR/commands.txt"
diff -u "$BASE_DIR/commands.txt" "$FINAL_DIR/commands.txt"

while IFS=: read -r type name image_type filename; do
  if [[ "$name" != rootfs ]]; then cmp "$BASE_DIR/$filename" "$FINAL_DIR/$filename"; fi
done < "$FINAL_DIR/commands.txt"

declare -A partitions
while IFS=: read -r type name image_type filename; do
  if [[ "$type" == PARTITION ]]; then
    partitions[$name]="$FINAL_DIR/$filename"
  elif [[ "$type" == VERIFY ]]; then
    expected=$(<"$FINAL_DIR/$filename")
    actual="sha1sum $(sha1sum "${partitions[$name]}" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || { echo "VERIFY mismatch for $name" >&2; exit 1; }
  fi
done < "$FINAL_DIR/commands.txt"

rootfs_sparse=$(awk -F: '$1 == "PARTITION" && $2 == "rootfs" {print $4; exit}' "$FINAL_DIR/commands.txt")
cmp --silent "$BASE_DIR/$rootfs_sparse" "$FINAL_DIR/$rootfs_sparse" && {
  echo 'rootfs was not changed' >&2
  exit 1
}
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$FINAL_DIR/$rootfs_sparse" "$ROOTFS_RAW"
as_root e2fsck -fn "$ROOTFS_RAW"
as_root mount -o loop,ro "$ROOTFS_RAW" "$MOUNT_DIR"

package_state=$(dpkg-query --admindir="$MOUNT_DIR/var/lib/dpkg" -W -f='${Status} ${Version} ${Architecture}' one-kvm)
libdrm_state=$(dpkg-query --admindir="$MOUNT_DIR/var/lib/dpkg" -W -f='${Status}' libdrm2)
binary_info=$(file "$MOUNT_DIR/usr/bin/one-kvm")
service_link=$(readlink "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/one-kvm.service" || true)
printf 'one-kvm=%q libdrm2=%q binary=%s service=%q\n' \
  "$package_state" "$libdrm_state" "$binary_info" "$service_link"
verify 'one-kvm package' test "$package_state" = "install ok installed $ONE_KVM_VERSION armhf"
verify 'libdrm2 package' test "$libdrm_state" = 'install ok installed'
verify 'ARM ELF binary' grep -q 'ELF 32-bit.*ARM' <<<"$binary_info"
verify 'one-kvm service link' test "$service_link" = /lib/systemd/system/one-kvm.service
verify 'one-kvm service unit' test -f "$MOUNT_DIR/lib/systemd/system/one-kvm.service"
verify 'OTG helper content' cmp "$ROOT_DIR/config/one-kvm-enable-otg" "$MOUNT_DIR/usr/sbin/one-kvm-enable-otg"
verify 'OTG systemd unit' cmp "$ROOT_DIR/config/one-kvm-otg.service" "$MOUNT_DIR/usr/lib/systemd/system/one-kvm-otg.service"
verify 'OTG drop-in' cmp "$ROOT_DIR/config/one-kvm.service.d-otg.conf" "$MOUNT_DIR/etc/systemd/system/one-kvm.service.d/otg.conf"
verify 'module configuration' cmp "$ROOT_DIR/config/one-kvm-modules.conf" "$MOUNT_DIR/etc/modules-load.d/one-kvm.conf"
verify 'OTG Wants dependency' grep -Fqx 'Wants=one-kvm-otg.service' "$MOUNT_DIR/etc/systemd/system/one-kvm.service.d/otg.conf"
verify 'OTG ordering dependency' grep -Fqx 'After=one-kvm-otg.service' "$MOUNT_DIR/etc/systemd/system/one-kvm.service.d/otg.conf"
verify 'libcomposite module' grep -Fqx 'libcomposite' "$MOUNT_DIR/etc/modules-load.d/one-kvm.conf"
verify 'image release metadata' node "$ROOT_DIR/scripts/verify-image-metadata.mjs" "$MOUNT_DIR/etc/ws1608-one-kvm-release"
verify 'OTG helper executable' test -x "$MOUNT_DIR/usr/sbin/one-kvm-enable-otg"
verify 'Deb removed after install' test ! -e "$MOUNT_DIR/tmp/one-kvm.deb"
verify 'qemu removed after install' test ! -e "$MOUNT_DIR/usr/bin/qemu-arm-static"
verify 'systemctl stub removed after install' test ! -e "$MOUNT_DIR/usr/local/sbin/systemctl"

as_root umount "$MOUNT_DIR"
trap - EXIT
mkdir -p "$(dirname "$VALIDATION_REPORT")"
node "$ROOT_DIR/scripts/write-validation-report.mjs" "$VALIDATION_REPORT"
verify 'validation report' test -s "$VALIDATION_REPORT"
echo "Verified $(basename "$IMAGE")"
