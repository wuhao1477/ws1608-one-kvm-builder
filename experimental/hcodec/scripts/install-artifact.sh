#!/usr/bin/env bash
set -Eeuo pipefail

ARTIFACT_DIR=${1:?usage: install-artifact.sh ARTIFACT_DIR TARGET_ROOT}
TARGET_ROOT=${2:?usage: install-artifact.sh ARTIFACT_DIR TARGET_ROOT}
MANIFEST="$ARTIFACT_DIR/manifest.json"
KERNEL_DIR="$ARTIFACT_DIR/kernel"
FIRMWARE_DIR="$ARTIFACT_DIR/firmware"

[[ -d "$ARTIFACT_DIR" && ! -L "$ARTIFACT_DIR" ]] || { echo 'invalid artifact directory' >&2; exit 1; }
[[ -d "$TARGET_ROOT" && ! -L "$TARGET_ROOT" ]] || { echo 'invalid target root' >&2; exit 1; }
[[ -s "$MANIFEST" && -s "$KERNEL_DIR/modules.tar.xz" && -s "$FIRMWARE_DIR/meson8b_h264.bin" ]] || { echo 'artifact payload is incomplete' >&2; exit 1; }
# 空间门槛按本候选真实需要计算，不用固定 4 GiB：原来的固定值在 8 GB eMMC 上
# 会随候选数量增长而必然误报（实测可用 3,670,940 KiB 时被拦下，而该候选实际只
# 需要约 250 MiB），迫使人工删除旧备份，反而更危险。
#
# 实际占用：解包出的模块树（staging）+ cp 到 /lib/modules 的第二份副本
# （staging 要到 trap 退出才删，两份同时存在）+ 内核与固件文件 + 旧内核文件备份。
modules_uncompressed_kib=$(
  xz --robot --list "$KERNEL_DIR/modules.tar.xz" | awk '$1 == "file" { print int($5 / 1024) + 1 }'
)
artifact_kib=$(du -sk "$ARTIFACT_DIR" | awk '{ print $1 }')
[[ "$modules_uncompressed_kib" =~ ^[0-9]+$ && "$modules_uncompressed_kib" -gt 0 ]] \
  || { echo 'cannot read uncompressed module tree size' >&2; exit 1; }
[[ "$artifact_kib" =~ ^[0-9]+$ && "$artifact_kib" -gt 0 ]] \
  || { echo 'cannot size artifact payload' >&2; exit 1; }
# 两份模块树 + 内核/固件写入 + 同等大小的备份，再留 64 MiB 余量给 ext4 元数据。
required_kib=$((modules_uncompressed_kib * 2 + artifact_kib * 2 + 65536))
target_avail=$(df -Pk "$TARGET_ROOT" | awk 'NR==2 { print $4 }')
[[ "$target_avail" =~ ^[0-9]+$ && "$target_avail" -ge "$required_kib" ]] || {
  echo "target root requires ${required_kib} KiB available, has ${target_avail:-0} KiB" >&2
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
for index in modules.order modules.dep modules.dep.bin modules.alias modules.alias.bin; do
  [[ -s "$module_tree/$index" ]] || { echo "module index missing: $index" >&2; exit 1; }
done
grep -Eq '^kernel/drivers/block/zram/zram\.ko: .*kernel/mm/zsmalloc\.ko' \
  "$module_tree/modules.dep" || {
  echo 'zram module dependency index is incomplete' >&2
  exit 1
}

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
  armbian_env=/boot/armbianEnv.txt
  if [[ -f "$armbian_env" ]]; then
    if grep -q '^extraargs=' "$armbian_env"; then
      sed -i 's/^extraargs=.*/extraargs=cma=128M/' "$armbian_env"
    else
      printf '\nextraargs=cma=128M\n' >>"$armbian_env"
    fi
  fi
fi

firmware_target="$TARGET_ROOT/lib/firmware/meson/venc/meson8b_h264.bin"
install -d -m 0755 "$(dirname "$firmware_target")"
install -m 0644 "$FIRMWARE_DIR/meson8b_h264.bin" "$firmware_target"

echo "installed kernel $KERNEL_RELEASE"
