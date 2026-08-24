#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source "$ROOT_DIR/experimental/amlenc/config/sources.env"
source "$ROOT_DIR/experimental/amlenc/config/legacy-bringup.env"

RECOVERY_ROOTFS_RAW=${RECOVERY_ROOTFS_RAW:?RECOVERY_ROOTFS_RAW is required}
LEGACY_MODULES_TAR=${LEGACY_MODULES_TAR:?LEGACY_MODULES_TAR is required}
SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:?SSH_PUBLIC_KEY is required}
OUTPUT_ROOTFS_RAW=${OUTPUT_ROOTFS_RAW:?OUTPUT_ROOTFS_RAW is required}
WORK_DIR=${WORK_DIR:-$ROOT_DIR/.build/amlenc/legacy-rootfs}

fail() { echo "legacy rootfs build failed: $*" >&2; exit 1; }
require_file() { [[ -f "$1" && ! -L "$1" && -s "$1" ]] || fail "invalid file: $1"; }
require_file "$RECOVERY_ROOTFS_RAW"
require_file "$LEGACY_MODULES_TAR"
[[ "$SSH_PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || fail "invalid SSH public key"
[[ "$WORK_DIR" != / && "$WORK_DIR" != "$ROOT_DIR" && ! -L "$WORK_DIR" ]] || fail "unsafe work directory"
[[ "$OUTPUT_ROOTFS_RAW" != / && ! -L "$OUTPUT_ROOTFS_RAW" ]] || fail "unsafe output path"
for command in docker realpath; do command -v "$command" >/dev/null || fail "missing command: $command"; done

mkdir -p "$WORK_DIR" "$(dirname "$OUTPUT_ROOTFS_RAW")"
find "$WORK_DIR" -mindepth 1 -delete
export SSH_PUBLIC_KEY

docker run --rm --platform linux/arm/v7 \
  -e SSH_PUBLIC_KEY \
  -v "$WORK_DIR:/work" \
  -v "$ROOT_DIR/experimental/amlenc/rootfs:/assets:ro" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/apt-install.sh:/build-tools/apt-install:ro" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/archive-rootfs.sh:/build-tools/archive-rootfs:ro" \
  "$BULLSEYE_ARMV7_OCI_IMAGE" sh -euxc '
    export DEBIAN_FRONTEND=noninteractive
    /build-tools/apt-install sysvinit-core initscripts udev kmod ifupdown \
      isc-dhcp-client openssh-server ca-certificates iproute2 procps psmisc util-linux
    printf "onecloud-amlenc\n" >/etc/hostname
    cat >/etc/network/interfaces <<"EOF"
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
EOF
    install -d -m 0700 /root/.ssh
    printf "%s\n" "$SSH_PUBLIC_KEY" >/root/.ssh/authorized_keys
    chmod 0600 /root/.ssh/authorized_keys
    passwd -l root
    install -D -m 0755 /assets/ws1608-amlenc-arm-trial /usr/local/sbin/ws1608-amlenc-arm-trial
    install -D -m 0755 /assets/ws1608-amlenc-mark-success /usr/local/sbin/ws1608-amlenc-mark-success
    install -d /boot /proc /sys /run/sshd
    cat >/etc/ssh/sshd_config.d/ws1608-amlenc.conf <<"EOF"
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
EOF
    cat >/etc/init.d/ws1608-amlenc-firstboot <<"EOF"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ws1608-amlenc-firstboot
# Required-Start:    $local_fs
# Required-Stop:
# Default-Start:     S
# Default-Stop:
### END INIT INFO
set -eu
mkdir -p /run/sshd
ssh-keygen -A
EOF
    chmod 0755 /etc/init.d/ws1608-amlenc-firstboot
    ln -s ../init.d/ws1608-amlenc-firstboot /etc/rcS.d/S01ws1608-amlenc-firstboot
    rm -f /etc/ssh/ssh_host_* /etc/machine-id
    : >/etc/machine-id
    find /var/lib/apt/lists /var/cache/apt/archives /tmp /var/tmp -mindepth 1 -delete
    /build-tools/archive-rootfs /work/rootfs.tar /
  '

recovery_dir=$(dirname "$(realpath "$RECOVERY_ROOTFS_RAW")")
legacy_dir=$(dirname "$(realpath "$LEGACY_MODULES_TAR")")
docker run --rm --platform linux/arm64 \
  -v "$WORK_DIR:/work" -v "$recovery_dir:/recovery:ro" -v "$legacy_dir:/legacy:ro" \
  -v "$ROOT_DIR/experimental/amlenc/scripts/apt-install.sh:/usr/local/bin/apt-install:ro" \
  "$IMAGE_TOOLS_ARM64_OCI_IMAGE" sh -euxc '
    apt-install e2fsprogs >/dev/null
    mkdir /work/rootfs-tree /work/recovery-tree
    tar --numeric-owner --xattrs --acls -xpf /work/rootfs.tar -C /work/rootfs-tree
    debugfs -R "rdump /lib/modules /work/recovery-tree" /recovery/'"${RECOVERY_ROOTFS_RAW##*/}"'
    debugfs -R "rdump /lib/firmware /work/recovery-tree" /recovery/'"${RECOVERY_ROOTFS_RAW##*/}"'
    test -d /work/recovery-tree/modules/'"$RECOVERY_KERNEL"'
    test '"$RECOVERY_KERNEL"' = 6.12.28-current-meson
    mkdir -p /work/rootfs-tree/lib/modules /work/rootfs-tree/lib/firmware
    cp -a /work/recovery-tree/modules/'"$RECOVERY_KERNEL"' /work/rootfs-tree/lib/modules/
    test -d /work/rootfs-tree/lib/modules/6.12.28-current-meson
    if test -d /work/recovery-tree/firmware; then cp -a /work/recovery-tree/firmware/. /work/rootfs-tree/lib/firmware/; fi
    tar -xzf /legacy/'"${LEGACY_MODULES_TAR##*/}"' -C /work/rootfs-tree
    test -d /work/rootfs-tree/lib/modules
    cat >/work/rootfs-tree/etc/fstab <<"EOF"
UUID='"$LEGACY_ROOTFS_UUID"' / ext4 defaults,errors=remount-ro 0 1
LABEL=armbi_boot /boot vfat defaults 0 2
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
tmpfs /run tmpfs mode=0755,nosuid,nodev 0 0
tmpfs /tmp tmpfs defaults,nosuid 0 0
EOF
    truncate -s '"$LEGACY_ROOTFS_BYTES"' /work/rootfs.raw
    mkfs.ext4 -F -L amlenc_root -U '"$LEGACY_ROOTFS_UUID"' \
      -O ^64bit,^metadata_csum,^orphan_file -d /work/rootfs-tree /work/rootfs.raw
    e2fsck -fy /work/rootfs.raw
  '

install -m 0644 "$WORK_DIR/rootfs.raw" "$OUTPUT_ROOTFS_RAW"
echo "built $OUTPUT_ROOTFS_RAW"
