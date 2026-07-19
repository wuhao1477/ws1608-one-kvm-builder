#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$ROOT_DIR/config/base.env"
source "$ROOT_DIR/config/tool-versions.env"
export BASE_ID BASE_KERNEL BASE_BOARD BASE_RELEASE_TAG BASE_IMAGE_NAME BASE_IMAGE_URL BASE_IMAGE_SHA256
export AMLIMG_REPOSITORY AMLIMG_COMMIT
IMAGE=${IMAGE:?IMAGE is required}
BASE_IMAGE=${BASE_IMAGE:?BASE_IMAGE is required}
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
VALIDATION_REPORT=${VALIDATION_REPORT:?VALIDATION_REPORT is required}
GITHUB_RUN_ID=${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}
GITHUB_RUN_ATTEMPT=${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT is required}
GITHUB_RUN_NUMBER=${GITHUB_RUN_NUMBER:?GITHUB_RUN_NUMBER is required}
VERIFY_ROOT=${VERIFY_DIR:-$ROOT_DIR/.verify}
export ONE_KVM_VERSION UPSTREAM_TAG PACKAGE_NAME PACKAGE_URL PACKAGE_DIGEST
export BUILD_TAG BUILD_NUMBER BUILD_REVISION BUILDER_COMMIT GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_RUN_NUMBER

for command in awk cmp diff dpkg-query e2fsck file find grep mount mountpoint node readlink readelf realpath sed sha1sum umount; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done
[[ -x "$AMLIMG_BIN" ]] || { echo "AmlImg binary is not executable: $AMLIMG_BIN" >&2; exit 1; }
[[ -f "$IMAGE" && ! -L "$IMAGE" ]] || { echo "invalid image: $IMAGE" >&2; exit 1; }
[[ -f "$BASE_IMAGE" && ! -L "$BASE_IMAGE" ]] || { echo "invalid base image: $BASE_IMAGE" >&2; exit 1; }
[[ ! -L "$VALIDATION_REPORT" ]] || { echo "validation report must not be a symlink" >&2; exit 1; }

as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

verify() {
  local name=$1
  shift
  if "$@"; then echo "verified: $name"; else echo "verification failed: $name" >&2; exit 1; fi
}

require_basename() {
  local value=$1 label=$2
  if [[ -z "$value" || "$value" == . || "$value" == .. || "$value" == *"/"* || "$value" == *"\\"* ]]; then
    echo "$label is not a basename: $value" >&2
    exit 1
  fi
}

mkdir -p "$VERIFY_ROOT"
[[ ! -L "$VERIFY_ROOT" ]] || { echo "VERIFY_DIR must not be a symlink: $VERIFY_ROOT" >&2; exit 1; }
VERIFY_WORK_DIR=$(mktemp -d "$VERIFY_ROOT/ws1608-verify.XXXXXX")
FINAL_DIR="$VERIFY_WORK_DIR/final"
BASE_DIR="$VERIFY_WORK_DIR/base"
ROOTFS_RAW="$VERIFY_WORK_DIR/rootfs.raw"
MOUNT_DIR="$VERIFY_WORK_DIR/rootfs.mnt"
root_mounted=false

cleanup() (
  set +e
  local failed=0
  if [[ "$root_mounted" == true ]] && mountpoint -q "$MOUNT_DIR"; then
    as_root umount "$MOUNT_DIR" || failed=1
  fi
  if mountpoint -q "$MOUNT_DIR"; then
    failed=1
  else
    as_root rm -rf -- "$VERIFY_WORK_DIR" || failed=1
  fi
  return "$failed"
)
on_exit() { local status=$?; trap - EXIT; cleanup || true; exit "$status"; }
trap on_exit EXIT

resolve_rootfs_path() {
  local guest=$1 root resolved
  [[ "$guest" == /* && "$guest" != *".."* ]] || { echo "invalid rootfs path: $guest" >&2; return 1; }
  root=$(realpath -e -- "$MOUNT_DIR")
  resolved=$(realpath -e -- "$MOUNT_DIR$guest") || return 1
  [[ "$resolved" == "$root"/* ]] || { echo "rootfs path escapes mount: $guest -> $resolved" >&2; return 1; }
  printf '%s\n' "$resolved"
}

mkdir -p "$FINAL_DIR" "$BASE_DIR" "$MOUNT_DIR"
"$AMLIMG_BIN" unpack "$IMAGE" "$FINAL_DIR"
"$AMLIMG_BIN" unpack "$BASE_IMAGE" "$BASE_DIR"
diff -u "$ROOT_DIR/config/commands.expected" "$FINAL_DIR/commands.txt"
diff -u "$BASE_DIR/commands.txt" "$FINAL_DIR/commands.txt"

while IFS=: read -r type name image_type filename; do
  require_basename "$filename" partition_file
  if [[ "$name" != rootfs ]]; then cmp "$BASE_DIR/$filename" "$FINAL_DIR/$filename"; fi
done < "$FINAL_DIR/commands.txt"

declare -A partitions
while IFS=: read -r type name image_type filename; do
  require_basename "$filename" command_file
  if [[ "$type" == PARTITION ]]; then
    partitions[$name]="$FINAL_DIR/$filename"
  elif [[ "$type" == VERIFY ]]; then
    [[ -n ${partitions[$name]:-} ]] || { echo "VERIFY precedes partition: $name" >&2; exit 1; }
    expected=$(<"$FINAL_DIR/$filename")
    actual="sha1sum $(sha1sum "${partitions[$name]}" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || { echo "VERIFY mismatch for $name" >&2; exit 1; }
  fi
done < "$FINAL_DIR/commands.txt"

rootfs_sparse=$(awk -F: '$1 == "PARTITION" && $2 == "rootfs" {print $4; exit}' "$FINAL_DIR/commands.txt")
require_basename "$rootfs_sparse" rootfs_partition
cmp --silent "$BASE_DIR/$rootfs_sparse" "$FINAL_DIR/$rootfs_sparse" && {
  echo 'rootfs was not changed' >&2
  exit 1
}
node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$FINAL_DIR/$rootfs_sparse" "$ROOTFS_RAW"
as_root e2fsck -fn "$ROOTFS_RAW"
as_root mount -o loop,ro "$ROOTFS_RAW" "$MOUNT_DIR"
root_mounted=true

dpkg_admin=$(resolve_rootfs_path /var/lib/dpkg)
tmp_dir=$(resolve_rootfs_path /tmp)
usr_bin_dir=$(resolve_rootfs_path /usr/bin)
usr_local_sbin_dir=$(resolve_rootfs_path /usr/local/sbin)
binary=$(resolve_rootfs_path /usr/bin/one-kvm)
service_unit=$(resolve_rootfs_path /lib/systemd/system/one-kvm.service)
metadata=$(resolve_rootfs_path /etc/ws1608-one-kvm-release)
otg_helper=$(resolve_rootfs_path /usr/sbin/one-kvm-enable-otg)
otg_unit=$(resolve_rootfs_path /usr/lib/systemd/system/one-kvm-otg.service)
otg_dropin=$(resolve_rootfs_path /etc/systemd/system/one-kvm.service.d/otg.conf)
modules_conf=$(resolve_rootfs_path /etc/modules-load.d/one-kvm.conf)

package_state=$(dpkg-query --admindir="$dpkg_admin" -W -f='${Status} ${Version} ${Architecture}' one-kvm)
for package in libdrm2 libc6 libgcc-s1 libstdc++6; do
  state=$(dpkg-query --admindir="$dpkg_admin" -W -f='${Status}' "$package")
  verify "$package package" test "$state" = 'install ok installed'
done
if dpkg-query --admindir="$dpkg_admin" -W libasound2t64 >/dev/null 2>&1; then
  libasound_package=libasound2t64
else
  libasound_package=libasound2
fi
libasound_state=$(dpkg-query --admindir="$dpkg_admin" -W -f='${Status}' "$libasound_package")
binary_info=$(file "$binary")
service_link=$(readlink "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/one-kvm.service" || true)
interpreter=$(readelf -l "$binary" | sed -n 's/.*Requesting program interpreter: \[\([^]]*\)\].*/\1/p')
needed_libraries=$(readelf -d "$binary" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
verify 'one-kvm package' test "$package_state" = "install ok installed $ONE_KVM_VERSION armhf"
verify "$libasound_package package" test "$libasound_state" = 'install ok installed'
verify 'ARM ELF binary' grep -q 'ELF 32-bit.*ARM' <<<"$binary_info"
verify 'ARM ELF machine' bash -c 'readelf -h "$1" | grep -Eq "Machine:[[:space:]]+ARM"' _ "$binary"
verify 'ARM dynamic loader declaration' test "$interpreter" = /lib/ld-linux-armhf.so.3
loader=$(resolve_rootfs_path "$interpreter")
verify 'ARM dynamic loader' test -f "$loader"
verify 'one-kvm service link' test "$service_link" = /lib/systemd/system/one-kvm.service
verify 'one-kvm service ExecStart' grep -Fqx 'ExecStart=/usr/bin/one-kvm' "$service_unit"
verify 'one-kvm service user' grep -Fqx 'User=root' "$service_unit"
verify 'OTG helper content' cmp "$ROOT_DIR/config/one-kvm-enable-otg" "$otg_helper"
verify 'OTG systemd unit' cmp "$ROOT_DIR/config/one-kvm-otg.service" "$otg_unit"
verify 'OTG drop-in' cmp "$ROOT_DIR/config/one-kvm.service.d-otg.conf" "$otg_dropin"
verify 'module configuration' cmp "$ROOT_DIR/config/one-kvm-modules.conf" "$modules_conf"
verify 'OTG Wants dependency' grep -Fqx 'Wants=one-kvm-otg.service' "$otg_dropin"
verify 'OTG ordering dependency' grep -Fqx 'After=one-kvm-otg.service' "$otg_dropin"
verify 'libcomposite module' grep -Fqx 'libcomposite' "$modules_conf"
verify 'image release metadata' node "$ROOT_DIR/scripts/verify-image-metadata.mjs" "$metadata"
verify 'OTG helper executable' test -x "$otg_helper"
verify 'Deb removed after install' test ! -e "$tmp_dir/one-kvm.deb"
verify 'qemu removed after install' test ! -e "$usr_bin_dir/qemu-arm-static"
verify 'systemctl stub removed after install' test ! -e "$usr_local_sbin_dir/systemctl"

while IFS= read -r library; do
  [[ -n "$library" ]] || continue
  library_path=$(find "$MOUNT_DIR/lib" "$MOUNT_DIR/usr/lib" -name "$library" -print -quit 2>/dev/null)
  [[ -n "$library_path" ]] || { echo "missing runtime library: $library" >&2; exit 1; }
  resolved_library=$(realpath -e "$library_path")
  [[ "$resolved_library" == "$(realpath -e "$MOUNT_DIR")"/* ]] || {
    echo "runtime library escapes rootfs: $library" >&2
    exit 1
  }
  echo "verified: runtime library $library"
done <<<"$needed_libraries"

cleanup
root_mounted=false
trap - EXIT
mkdir -p "$(dirname "$VALIDATION_REPORT")"
node "$ROOT_DIR/scripts/write-validation-report.mjs" "$VALIDATION_REPORT"
verify 'validation report' test -s "$VALIDATION_REPORT"
echo "Verified $(basename "$IMAGE")"
