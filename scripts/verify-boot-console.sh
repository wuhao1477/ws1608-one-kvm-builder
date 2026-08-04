#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
BOOT_IMAGE=${1:?boot FAT image is required}
OUTPUT_DIR=${2:?output directory is required}

for command in mcopy node; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done
[[ -f "$BOOT_IMAGE" && ! -L "$BOOT_IMAGE" ]] || { echo "invalid boot image: $BOOT_IMAGE" >&2; exit 1; }
[[ ! -L "$OUTPUT_DIR" ]] || { echo "output directory must not be a symlink" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR"
for file in armbianEnv.txt boot.cmd; do
  target="$OUTPUT_DIR/$file"
  [[ ! -L "$target" ]] || { echo "output file must not be a symlink: $target" >&2; exit 1; }
  mcopy -o -i "$BOOT_IMAGE" "::$file" "$target"
done
node "$ROOT_DIR/scripts/verify-boot-console.mjs" \
  "$OUTPUT_DIR/armbianEnv.txt" "$OUTPUT_DIR/boot.cmd"
