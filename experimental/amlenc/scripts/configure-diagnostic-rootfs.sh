#!/usr/bin/env bash
set -euo pipefail

ROOTFS=${1:?rootfs directory is required}
PUBLIC_KEY=${AMLENC_SSH_PUBLIC_KEY:-}
[[ -d "$ROOTFS" && ! -L "$ROOTFS" ]] || { echo "rootfs directory is unsafe" >&2; exit 1; }
[[ "$PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || {
  echo "AMLENC_SSH_PUBLIC_KEY must contain one OpenSSH public key" >&2
  exit 1
}

install -d -m 0700 "$ROOTFS/root/.ssh"
install -d -m 0755 "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run"
printf '%s\n' "$PUBLIC_KEY" >"$ROOTFS/root/.ssh/authorized_keys"
chmod 0600 "$ROOTFS/root/.ssh/authorized_keys"

install -d -m 0755 "$ROOTFS/etc/ssh/sshd_config.d"
cat >"$ROOTFS/etc/ssh/sshd_config.d/ws1608-amlenc.conf" <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF

install -d -m 0755 "$ROOTFS/etc/network"
cat >"$ROOTFS/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

allow-hotplug eth0
iface eth0 inet dhcp
EOF

install -d -m 0755 "$ROOTFS/etc/init.d" "$ROOTFS/etc/rcS.d"
cat >"$ROOTFS/etc/init.d/ws1608-amlenc-firstboot" <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ws1608-amlenc-firstboot
# Required-Start:    $local_fs $remote_fs
# Required-Stop:
# Default-Start:     S
# Default-Stop:
# Short-Description: Initialize WS1608 AMLENC diagnostic host
### END INIT INFO
set -eu
ssh-keygen -A
mkdir -p /run/sshd /var/lib/ws1608-amlenc
chmod 0700 /run/sshd
touch /var/lib/ws1608-amlenc/firstboot-complete
exit 0
EOF
chmod 0755 "$ROOTFS/etc/init.d/ws1608-amlenc-firstboot"
ln -s ../init.d/ws1608-amlenc-firstboot "$ROOTFS/etc/rcS.d/S99ws1608-amlenc-firstboot"

install -d -m 0755 "$ROOTFS/usr/local/sbin"
cat >"$ROOTFS/usr/local/sbin/ws1608-amlenc-probe" <<'EOF'
#!/bin/sh
set -eu
probe=${1:-}
input=${2:-}
case "$probe" in
  640x480-300f) width=640; height=480; bitrate=1000000; frames=300 ;;
  1280x720-1800f) width=1280; height=720; bitrate=4000000; frames=1800 ;;
  1280x720-8h) width=1280; height=720; bitrate=4000000; frames=864000 ;;
  *) echo "usage: $0 PROBE INPUT_NV12" >&2; exit 2 ;;
esac
[ -f "$input" ] || { echo "NV12 input frame is missing" >&2; exit 1; }
output_root=/var/lib/ws1608-amlenc/results
mkdir -p "$output_root"
output="$output_root/$probe.h264"
kernel_log="$output_root/$probe.dmesg"
LD_LIBRARY_PATH=/usr/local/lib/ws1608-amlenc \
  /usr/local/libexec/ws1608-amlenc/amlenc-m8-diag \
  --input "$input" --width "$width" --height "$height" --fps 30 \
  --bitrate "$bitrate" --frames "$frames" --output "$output"
dmesg >"$kernel_log"
AMLENC_HARDWARE_LIMITS=/usr/local/share/ws1608-amlenc/hardware-limits.json \
  /usr/local/libexec/ws1608-amlenc/validate-h264.sh \
  --probe "$probe" --input "$output" --kernel-log "$kernel_log" \
  --output-dir "$output_root/$probe-evidence"
EOF
chmod 0755 "$ROOTFS/usr/local/sbin/ws1608-amlenc-probe"
