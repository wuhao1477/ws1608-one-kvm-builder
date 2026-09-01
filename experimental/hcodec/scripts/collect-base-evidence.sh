#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
SOURCES="$ROOT_DIR/experimental/hcodec/config/sources.env"

fail() { echo "base evidence failed: $*" >&2; exit 1; }
sha256_of() { sha256sum "$1" | awk '{print $1}'; }

load_sources() {
  node "$ROOT_DIR/experimental/hcodec/scripts/verify-source-locks.mjs" "$SOURCES"
  set -a
  # shellcheck disable=SC1090
  source "$SOURCES"
  set +a
}

verify_evidence() {
  local input=$1 output=$2
  [[ -d "$input" && ! -L "$input" ]] || fail "unsafe input directory"
  [[ -n "$output" && "$output" != / && ! -L "$output" ]] || fail "unsafe output directory"
  local files=(armbian-release linux-image-metadata kernel.config kernel.config.sha256
    uimage-header.json armbianEnv.txt boot.cmd dtb.sha256)
  for file in "${files[@]}"; do
    [[ -s "$input/$file" && ! -L "$input/$file" ]] || fail "missing $file"
  done

  local build_short
  build_short=$(sed -n 's/^BUILD_REPOSITORY_COMMIT=//p' "$input/armbian-release")
  [[ "$ARMBIAN_BUILD_COMMIT" == "$build_short"* ]] || fail "Armbian build commit does not match"
  grep -Fq "VERSION=$ARMBIAN_VERSION" "$input/armbian-release" || fail "Armbian version does not match"
  grep -Fq "git revision \"$LINUX_COMMIT\"" "$input/linux-image-metadata" || fail "kernel commit does not match"
  grep -Fq ".config hash \"$ARMBIAN_CONFIG_HASH\"" "$input/linux-image-metadata" || fail "Armbian config hash does not match"
  grep -Fq "patches hash \"$ARMBIAN_PATCHES_HASH\"" "$input/linux-image-metadata" || fail "Armbian patches hash does not match"
  [[ "$(tr -d '\r\n' <"$input/kernel.config.sha256")" == "$KERNEL_CONFIG_SHA256" ]] || fail "kernel config SHA-256 does not match"
  [[ "$(tr -d '\r\n' <"$input/dtb.sha256")" == "$BASE_DTB_SHA256" ]] || fail "DTB SHA-256 does not match"
  grep -Fq '# CONFIG_MODULE_SIG is not set' "$input/kernel.config" || fail "module signing policy does not match"
  grep -Fq 'fatload ${bootdev} 0x20800000 /uImage' "$input/boot.cmd" || fail "U-Boot load address does not match"

  local header load entry boot_load
  header=$(node -e '
    const fs = require("fs"); const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    for (const key of ["load_address", "entry_point", "boot_load_address"])
      if (typeof value[key] !== "string") process.exit(2);
    process.stdout.write([value.load_address, value.entry_point, value.boot_load_address].join(" "));
  ' "$input/uimage-header.json") || fail "invalid uImage header"
  read -r load entry boot_load <<<"$header"
  [[ "$load" == "$UIMAGE_LOAD_ADDRESS" && "$entry" == "$UIMAGE_ENTRY_POINT" && "$boot_load" == "$UBOOT_LOAD_ADDRESS" ]] \
    || fail "uImage address does not match"

  mkdir -p "$output"
  cp "${files[@]/#/$input/}" "$output/"
  node - "$output/evidence-manifest.json" "$ARMBIAN_BUILD_COMMIT" "$LINUX_COMMIT" \
    "$KERNEL_CONFIG_SHA256" "$BASE_DTB_SHA256" "$load" "$entry" "$boot_load" <<'NODE'
const fs = require('fs');
const [file, armbian, linux, config, dtb, load, entry, boot] = process.argv.slice(2);
const manifest = { schema: 1, board: 'onecloud', arch: 'arm', kernel_release: '6.12.28-current-meson',
  armbian_build_commit: armbian, linux_commit: linux, kernel_config_sha256: config, dtb_sha256: dtb,
  module_signing: 'disabled', uimage: { load_address: load, entry_point: entry, boot_load_address: boot } };
fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
  echo "verified stable Armbian base evidence"
}

collect_evidence() {
  local output=$1
  local base=${BASE_IMAGE_XZ:-}
  local amlimg=${AMLIMG_BIN:-}
  [[ -n "$base" ]] || fail "BASE_IMAGE_XZ is required"
  [[ -f "$base" && ! -L "$base" ]] || fail "invalid BASE_IMAGE_XZ"
  [[ -x "$amlimg" ]] || fail "AMLIMG_BIN is required"
  for command in xz node mcopy debugfs awk sed sha256sum; do command -v "$command" >/dev/null || fail "missing command: $command"; done
  [[ "$(sha256_of "$base")" == "$BASE_IMAGE_SHA256" ]] || fail "base image SHA-256 does not match"

  local work=${HCODEC_EVIDENCE_WORK_DIR:-$ROOT_DIR/.build/hcodec/base-evidence}
  [[ "$work" != / && "$work" != "$ROOT_DIR" && ! -L "$work" ]] || fail "unsafe work directory"
  rm -rf "$work"
  mkdir -p "$work/unpacked" "$work/input"
  xz -dc "$base" >"$work/base.burn.img"
  "$amlimg" unpack "$work/base.burn.img" "$work/unpacked"
  node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$work/unpacked/3.boot.PARTITION.sparse" "$work/boot.raw"
  node "$ROOT_DIR/scripts/sparse-to-raw.mjs" "$work/unpacked/10.rootfs.PARTITION.sparse" "$work/rootfs.raw"

  for item in armbianEnv.txt boot.cmd config-6.12.28-current-meson uImage dtb/meson8b-onecloud.dtb; do
    mcopy -o -i "$work/boot.raw" "::$item" "$work/input/${item##*/}"
  done
  debugfs -R 'cat /etc/armbian-release' "$work/rootfs.raw" 2>/dev/null >"$work/input/armbian-release"
  debugfs -R 'cat /var/lib/dpkg/status' "$work/rootfs.raw" 2>/dev/null >"$work/dpkg-status"
  awk 'BEGIN { RS="" } /^Package: linux-image-current-meson\n/ { print; exit }' \
    "$work/dpkg-status" >"$work/input/linux-image-metadata"
  mv "$work/input/config-6.12.28-current-meson" "$work/input/kernel.config"
  printf '%s\n' "$(sha256_of "$work/input/kernel.config")" >"$work/input/kernel.config.sha256"
  printf '%s\n' "$(sha256_of "$work/input/meson8b-onecloud.dtb")" >"$work/input/dtb.sha256"
  local boot_load
  boot_load=$(sed -nE 's#.*fatload \$\{bootdev\} (0x[0-9A-Fa-f]+) /uImage.*#\1#p' "$work/input/boot.cmd")
  node - "$work/input/uImage" "$work/input/uimage-header.json" "$boot_load" <<'NODE'
const fs = require('fs'); const [input, output, boot] = process.argv.slice(2);
const data = fs.readFileSync(input); if (data.length < 64 || data.readUInt32BE(0) !== 0x27051956) process.exit(2);
const hex = (value) => `0x${value.toString(16).padStart(8, '0')}`;
fs.writeFileSync(output, `${JSON.stringify({ load_address: hex(data.readUInt32BE(16)),
  entry_point: hex(data.readUInt32BE(20)), boot_load_address: boot }, null, 2)}\n`);
NODE
  rm -f "$work/input/uImage" "$work/input/meson8b-onecloud.dtb"
  verify_evidence "$work/input" "$output"
}

load_sources
case ${1:-} in
  verify) verify_evidence "${2:-}" "${3:-}" ;;
  collect) collect_evidence "${2:-}" ;;
  *) fail "usage: $0 verify INPUT_DIR OUTPUT_DIR | collect OUTPUT_DIR" ;;
esac
