#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SOURCES_FILE="$ROOT_DIR/experimental/amlenc/config/sources.env"
KERNEL_DIR=${AMLENC_KERNEL_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/kernel}
ENCODER_DIR=${AMLENC_LIBVPCODEC_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/libvpcodec}
OUTPUT_DIR=${AMLENC_DIAGNOSTIC_IMAGE_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/diagnostic-image}
BUILD_REVISION=${AMLENC_BUILD_REVISION:-local001}

fail() {
  echo "diagnostic image input audit failed: $*" >&2
  exit 1
}

require_regular_file() {
  local file=$1 label=$2
  [[ -f "$file" && ! -L "$file" && -s "$file" ]] || fail "$label is missing or unsafe"
}

prepare_output_dir() {
  [[ "$OUTPUT_DIR" != / && "$OUTPUT_DIR" != "$ROOT_DIR" && ! -L "$OUTPUT_DIR" ]] ||
    fail "output directory is unsafe"
  if [[ -d "$OUTPUT_DIR" ]]; then
    [[ -z "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
      fail "output directory must be empty"
  elif [[ -e "$OUTPUT_DIR" ]]; then
    fail "output directory must be a directory"
  else
    mkdir -p "$OUTPUT_DIR"
  fi
}

verify_checksums() {
  local directory=$1 label=$2
  require_regular_file "$directory/SHA256SUMS" "$label checksum list"
  if ! (cd "$directory" && sha256sum --check --strict SHA256SUMS >/dev/null); then
    fail "$label checksum verification failed"
  fi
}

write_input_manifest() {
  local kernel_manifest=$KERNEL_DIR/source-manifest.json
  local encoder_manifest=$ENCODER_DIR/source-manifest.json
  local image_name="WS1608-AMLENC-Diagnostic_k3.10.107_bullseye_${BUILD_REVISION}.usb.img"
  local kernel_commit encoder_commit kernel_version encoder_abi redistribution

  kernel_commit=$(jq -er '.commit' "$kernel_manifest")
  kernel_version=$(jq -er '.kernel' "$kernel_manifest")
  encoder_commit=$(jq -er '.commit' "$encoder_manifest")
  encoder_abi=$(jq -er '.abi' "$encoder_manifest")
  redistribution=$(jq -er '.redistribution' "$encoder_manifest")

  jq -n \
    --arg image_name "$image_name" --arg revision "$BUILD_REVISION" \
    --arg kernel_commit "$kernel_commit" --arg kernel_version "$kernel_version" \
    --arg encoder_commit "$encoder_commit" --argjson encoder_abi "$encoder_abi" \
    --arg redistribution "$redistribution" \
    --arg zimage "$(sha256sum "$KERNEL_DIR/zImage" | awk '{print $1}')" \
    --arg dtb "$(sha256sum "$KERNEL_DIR/ws1608-s805.dtb" | awk '{print $1}')" \
    --arg modules "$(sha256sum "$KERNEL_DIR/modules.tar.gz" | awk '{print $1}')" \
    --arg kernel_config "$(sha256sum "$KERNEL_DIR/kernel.config" | awk '{print $1}')" \
    --arg library "$(sha256sum "$ENCODER_DIR/libvpcodec.so" | awk '{print $1}')" \
    --arg diagnostic "$(sha256sum "$ENCODER_DIR/amlenc-m8-diag" | awk '{print $1}')" '
    {
      schema: 1,
      kind: "ws1608-amlenc-diagnostic-usb-image",
      image_name: $image_name,
      build_revision: $revision,
      userspace: "debian-bullseye-armhf",
      partition_layout: {
        boot_start_mib: 16,
        boot_size_mib: 256,
        rootfs_start_mib: 272,
        rootfs_size_bytes: 1400897536
      },
      kernel: {version: $kernel_version, commit: $kernel_commit},
      encoder: {abi: $encoder_abi, commit: $encoder_commit, redistribution: $redistribution},
      inputs: {
        zImage: $zimage,
        dtb: $dtb,
        modules: $modules,
        kernel_config: $kernel_config,
        libvpcodec: $library,
        diagnostic: $diagnostic
      },
      hardware_encoder_tested: false,
      one_kvm_included: false,
      stable_channel_modified: false
    }
  ' >"$OUTPUT_DIR/input-manifest.json"
}

audit_inputs() {
  [[ "$BUILD_REVISION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$ ]] ||
    fail "build revision is unsafe"
  require_regular_file "$SOURCES_FILE" "source locks"
  for file in zImage ws1608-s805.dtb modules.tar.gz kernel.config source-manifest.json; do
    require_regular_file "$KERNEL_DIR/$file" "kernel artifact $file"
  done
  for file in libvpcodec.so amlenc-m8-diag source-manifest.json; do
    require_regular_file "$ENCODER_DIR/$file" "encoder artifact $file"
  done
  verify_checksums "$KERNEL_DIR" kernel
  verify_checksums "$ENCODER_DIR" encoder

  # shellcheck disable=SC1090
  source "$SOURCES_FILE"
  jq -e --arg commit "$LINUX_COMMIT" --arg version "$KERNEL_VERSION" \
    '.schema == 1 and .commit == $commit and .kernel == $version' \
    "$KERNEL_DIR/source-manifest.json" >/dev/null || fail "kernel identity mismatch"
  jq -e --arg commit "$LIBENCODER_COMMIT" \
    '.schema == 1 and .commit == $commit and .abi == 1 and
      .architecture == "armhf" and .redistribution == "local-test-only"' \
    "$ENCODER_DIR/source-manifest.json" >/dev/null || fail "encoder identity mismatch"

  prepare_output_dir
  write_input_manifest
  echo "audited WS1608 AMLENC diagnostic image inputs"
}

build_image() {
  audit_inputs
  "$ROOT_DIR/experimental/amlenc/scripts/assemble-diagnostic-usb.sh"
  "$ROOT_DIR/experimental/amlenc/scripts/verify-diagnostic-usb.sh"
}

case ${1:-} in
  --audit-inputs) audit_inputs ;;
  --build) build_image ;;
  *) fail "unsupported mode; use --audit-inputs or --build" ;;
esac
