#!/usr/bin/env bash
set -Eeuo pipefail

ARTIFACT_DIR=${1:?usage: install-artifact.sh ARTIFACT_DIR TARGET_ROOT}
TARGET_ROOT=${2:?usage: install-artifact.sh ARTIFACT_DIR TARGET_ROOT}
MANIFEST="$ARTIFACT_DIR/manifest.json"
KERNEL_DIR="$ARTIFACT_DIR/kernel"

[[ -d "$ARTIFACT_DIR" && ! -L "$ARTIFACT_DIR" ]] || { echo 'invalid artifact directory' >&2; exit 1; }
[[ -d "$TARGET_ROOT" && ! -L "$TARGET_ROOT" ]] || { echo 'invalid target root' >&2; exit 1; }
[[ -s "$MANIFEST" && -s "$KERNEL_DIR/modules.tar.xz" ]] || { echo 'artifact kernel payload is incomplete' >&2; exit 1; }
target_avail=$(df -Pk "$TARGET_ROOT" | awk 'NR==2 {print $4}')
[[ "$target_avail" =~ ^[0-9]+$ && "$target_avail" -ge 4000000 ]] || {
  echo 'target root requires at least 4 GiB available' >&2
  exit 1
}

KERNEL_RELEASE=$(python3 - "$MANIFEST" <<'PY'
import json
import re
import sys

value = json.load(open(sys.argv[1], encoding='utf-8'))
release = value.get('kernel_release', '')
if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+-current-meson', release):
    raise SystemExit(1)
print(release)
PY
)

for file in uImage System.map kernel.config meson8b-onecloud.dtb; do
  [[ -s "$KERNEL_DIR/$file" ]] || { echo "missing kernel file: $file" >&2; exit 1; }
done

modules_stage=$(mktemp -d "$TARGET_ROOT/root/hcodec-modules-stage.XXXXXX")
cleanup() { rm -rf "$modules_stage"; }
trap cleanup EXIT
tar -xJf "$KERNEL_DIR/modules.tar.xz" -C "$modules_stage" --no-same-owner
module_tree="$modules_stage/lib/modules/$KERNEL_RELEASE"
[[ -d "$module_tree" && ! -L "$module_tree" ]] || { echo 'module tree is missing' >&2; exit 1; }

backup_dir="$TARGET_ROOT/root/hcodec/backups/install-$(date -u +%Y%m%dT%H%M%SZ)"
install -d "$backup_dir"
for file in boot/uImage "boot/System.map-$KERNEL_RELEASE" "boot/config-$KERNEL_RELEASE" \
  boot/dtb/meson8b-onecloud.dtb boot/armbianEnv.txt; do
  if [[ -e "$TARGET_ROOT/$file" || -L "$TARGET_ROOT/$file" ]]; then
    cp -a "$TARGET_ROOT/$file" "$backup_dir/"
  fi
done

install -d "$TARGET_ROOT/boot" "$TARGET_ROOT/boot/dtb"
install -m 0755 "$KERNEL_DIR/uImage" "$TARGET_ROOT/boot/uImage"
install -m 0644 "$KERNEL_DIR/System.map" "$TARGET_ROOT/boot/System.map-$KERNEL_RELEASE"
install -m 0644 "$KERNEL_DIR/kernel.config" "$TARGET_ROOT/boot/config-$KERNEL_RELEASE"
install -m 0644 "$KERNEL_DIR/meson8b-onecloud.dtb" "$TARGET_ROOT/boot/dtb/meson8b-onecloud.dtb"

mkdir -p "$TARGET_ROOT/lib/modules"
rm -rf -- "$TARGET_ROOT/lib/modules/$KERNEL_RELEASE"
cp -a "$module_tree" "$TARGET_ROOT/lib/modules/"

if [[ "$TARGET_ROOT" == / ]]; then
  command -v depmod >/dev/null 2>&1 || { echo 'depmod is required for a live-root install' >&2; exit 1; }
  depmod "$KERNEL_RELEASE"
  armbian_env=/boot/armbianEnv.txt
  if [[ -f "$armbian_env" ]]; then
    if grep -q '^extraargs=' "$armbian_env"; then
      sed -i 's/^extraargs=.*/extraargs=cma=128M/' "$armbian_env"
    else
      printf '\nextraargs=cma=128M\n' >>"$armbian_env"
    fi
  fi
fi

firmware_source="$TARGET_ROOT/lib/firmware/video/h264_enc.bin"
firmware_target="$TARGET_ROOT/lib/firmware/meson/venc/meson8b_h264.bin"
if [[ -s "$firmware_source" ]]; then
  install -d -m 0755 "$(dirname "$firmware_target")"
  python3 - "$firmware_source" "$firmware_target" <<'PY'
import struct
import sys
import zlib

source, target = sys.argv[1:]
blob = open(source, 'rb').read()
offset = 256
while offset + 256 <= len(blob):
    name = blob[offset:offset + 32].split(b'\0', 1)[0].decode('ascii', 'replace')
    length = struct.unpack_from('<I', blob, offset + 96)[0]
    if not length:
        break
    fw = offset + 256
    size = struct.unpack_from('<I', blob, fw + 200)[0]
    if name in {'gxl_h264_enc', 'gxl_h264_enc.bin'}:
        data = blob[fw + 512:fw + 512 + size]
        if struct.unpack_from('<I', blob, fw)[0] != 0x434f4445:
            raise SystemExit('invalid H.264 firmware record')
        if zlib.crc32(data) & 0xffffffff != struct.unpack_from('<I', blob, fw + 4)[0]:
            raise SystemExit('H.264 firmware CRC mismatch')
        open(target, 'wb').write(data)
        break
    offset += 256 + length
else:
    raise SystemExit('GXL H.264 firmware record missing')
PY
  chmod 0644 "$firmware_target"
fi

echo "installed kernel $KERNEL_RELEASE"
