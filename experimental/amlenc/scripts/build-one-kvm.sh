#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CONFIG_FILE="$ROOT_DIR/experimental/amlenc/config/sources.env"
PATCH_DIR="$ROOT_DIR/experimental/amlenc/patches/one-kvm"
LOCK_DIR="$ROOT_DIR/experimental/amlenc/locks/one-kvm"
SOFTWARE_CODECS_FILE="$ROOT_DIR/experimental/amlenc/config/software-codecs.json"
WORK_DIR=${AMLENC_WORK_DIR:-$ROOT_DIR/.build/amlenc}
SOURCE_DIR="$WORK_DIR/one-kvm-source"
OUTPUT_DIR=${AMLENC_ONE_KVM_OUTPUT_DIR:-$ROOT_DIR/out/amlenc/one-kvm}
TARGET=armv7-unknown-linux-gnueabihf
BUILD_NUMBER=${BUILD_NUMBER:-local001}
BUILD_DRIVER=${AMLENC_BUILD_DRIVER:-cross}
CROSS_IMAGE=${AMLENC_CROSS_IMAGE:-}

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a
RUST_TOOLCHAIN=$ONE_KVM_RUST_TOOLCHAIN
PNPM_VERSION=$ONE_KVM_PNPM_VERSION
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$ONE_KVM_SOURCE_DATE_EPOCH}
node "$ROOT_DIR/experimental/amlenc/scripts/verify-source-locks.mjs" "$CONFIG_FILE"
[[ "$BUILD_NUMBER" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,31}$ ]]
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]{10}$ ]]
[[ "$ONE_KVM_COMMIT" =~ ^[0-9a-f]{40}$ ]]
[[ "$ONE_KVM_ARCHIVE_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$ONE_KVM_ARCHIVE_URL" == "https://codeload.github.com/mofeng-git/One-KVM/tar.gz/$ONE_KVM_COMMIT" ]]
for command in curl sha256sum dpkg-deb corepack node; do command -v "$command" >/dev/null || exit 1; done
command -v "$BUILD_DRIVER" >/dev/null || exit 1
[[ -f "$LOCK_DIR/Cargo.lock" && -f "$LOCK_DIR/pnpm-lock.yaml" && -f "$SOFTWARE_CODECS_FILE" ]]
jq -e '
  .schema == 1 and .codecs == [
    {id:"h264",encoder:"libx264",decoder:"h264"},
    {id:"h265",encoder:"libx265",decoder:"hevc"},
    {id:"vp8",encoder:"libvpx",decoder:"vp8"},
    {id:"vp9",encoder:"libvpx-vp9",decoder:"vp9"}
  ]
' "$SOFTWARE_CODECS_FILE" >/dev/null

VERSION="${ONE_KVM_VERSION}+ws1608amlenc.${BUILD_NUMBER}"
ARCHIVE="$WORK_DIR/one-kvm-$ONE_KVM_COMMIT.tar.gz"
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
if [[ ! -f "$ARCHIVE" ]]; then curl --fail --location --retry 5 "$ONE_KVM_ARCHIVE_URL" -o "$ARCHIVE"; fi
printf '%s  %s\n' "$ONE_KVM_ARCHIVE_SHA256" "$ARCHIVE" | sha256sum --check

rm -rf "$SOURCE_DIR"
mkdir -p "$SOURCE_DIR"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIR" --strip-components=1
git -C "$SOURCE_DIR" init -q
git -C "$SOURCE_DIR" add --all
git -C "$SOURCE_DIR" -c user.name=builder -c user.email=noreply@github.com -c commit.gpgsign=false commit -q -m baseline
for patch in "$PATCH_DIR"/*.patch; do
  git -C "$SOURCE_DIR" apply --check "$patch"
  git -C "$SOURCE_DIR" apply "$patch"
done
dockerfile="$SOURCE_DIR/build/cross/Dockerfile.armv7"
for expected in \
  "ARG DEBIAN_IMAGE=$ONE_KVM_ARMV7_OCI_IMAGE" \
  "ARG RUST_TOOLCHAIN=$ONE_KVM_RUST_TOOLCHAIN" \
  "ARG X264_REV=$ONE_KVM_X264_COMMIT" \
  "ARG RKMPP_REV=$ONE_KVM_RKMPP_COMMIT" \
  "ARG RKRGA_REV=$ONE_KVM_RKRGA_COMMIT"; do
  grep -Fqx "$expected" "$dockerfile" || { echo "unpinned ARMv7 input: $expected" >&2; exit 1; }
done
sed -i.bak -E "0,/^version = \"[0-9.]+\"/s//version = \"$VERSION\"/" "$SOURCE_DIR/Cargo.toml"
rm -f "$SOURCE_DIR/Cargo.toml.bak"
cp "$LOCK_DIR/Cargo.lock" "$SOURCE_DIR/Cargo.lock"
cp "$LOCK_DIR/pnpm-lock.yaml" "$SOURCE_DIR/web/pnpm-lock.yaml"
(cd "$SOURCE_DIR" && PACKAGE_VERSION="$VERSION" node <<'NODE'
const fs = require('node:fs');
const lockPath = 'Cargo.lock';
const lock = fs.readFileSync(lockPath, 'utf8');
const updated = lock.replace(
  /(\[\[package\]\]\nname = "one-kvm"\nversion = ")[^"]+("\n)/,
  `$1${process.env.PACKAGE_VERSION}$2`,
);
if (updated === lock) throw new Error('one-kvm package version was not found in Cargo.lock');
fs.writeFileSync(lockPath, updated);
NODE
)
git -C "$SOURCE_DIR" add --all
git -C "$SOURCE_DIR" -c user.name=builder -c user.email=noreply@github.com -c commit.gpgsign=false commit -q -m patched-source

(cd "$SOURCE_DIR/web" && SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
  corepack "pnpm@$PNPM_VERSION" install --frozen-lockfile && \
  SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" corepack "pnpm@$PNPM_VERSION" run build)
if [[ -n "$CROSS_IMAGE" ]]; then
  CROSS_CONFIG="$SOURCE_DIR/Cross.toml" CROSS_IMAGE="$CROSS_IMAGE" \
    "$ROOT_DIR/experimental/amlenc/scripts/prepare-one-kvm-cross-image.sh" \
    "$SOURCE_DIR" "$CROSS_IMAGE"
fi
if [[ -n "$CROSS_IMAGE" ]]; then
  (export CROSS_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_IMAGE="$CROSS_IMAGE"
   cd "$SOURCE_DIR"
   SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
     "$BUILD_DRIVER" build --locked --release --target "$TARGET")
else
  (cd "$SOURCE_DIR" && SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    "$BUILD_DRIVER" build --locked --release --target "$TARGET")
fi
SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" "$SOURCE_DIR/build/package-deb.sh" armhf
base_deb=$(find "$SOURCE_DIR/target/debian" -maxdepth 1 -type f -name "one-kvm_${VERSION}_armhf.deb" -print -quit)
[[ -f "$base_deb" ]]

package_dir=$(mktemp -d "$WORK_DIR/one-kvm-package.XXXXXX")
control_dir=$(mktemp -d "$WORK_DIR/one-kvm-control.XXXXXX")
trap 'rm -rf "$package_dir" "$control_dir"' EXIT
dpkg-deb -x "$base_deb" "$package_dir"
dpkg-deb -e "$base_deb" "$control_dir"
cp -a "$control_dir" "$package_dir/DEBIAN"
install -d "$package_dir/usr/lib/one-kvm" "$package_dir/usr/share/doc/one-kvm"
install -m 0755 "$ROOT_DIR/out/amlenc/libvpcodec/amlenc-m8-diag" "$package_dir/usr/lib/one-kvm/amlenc-m8-diag"
install -m 0644 "$ROOT_DIR/out/amlenc/libvpcodec/libvpcodec.so" "$package_dir/usr/lib/one-kvm/libvpcodec.so"
sed -i 's#^ExecStart=/usr/bin/one-kvm#Environment=ONE_KVM_AMLENC_H264_LIB=/usr/lib/one-kvm/libvpcodec.so\nExecStart=/usr/bin/one-kvm#' "$package_dir/lib/systemd/system/one-kvm.service"
patch_digest=$("$ROOT_DIR/experimental/amlenc/scripts/one-kvm-patch-digest.sh" "$PATCH_DIR")
dependency_locks_digest=$(cd "$LOCK_DIR" && sha256sum Cargo.lock pnpm-lock.yaml | sha256sum | awk '{print $1}')
metadata="$package_dir/usr/share/doc/one-kvm/ws1608-amlenc-build.json"
software_codecs=$(jq -c '[.codecs[] + {hardware:false}]' "$SOFTWARE_CODECS_FILE")
jq -cn \
  --arg repository "$ONE_KVM_REPOSITORY" --arg ref "$ONE_KVM_REF" --arg commit "$ONE_KVM_COMMIT" \
  --arg upstream_version "$ONE_KVM_VERSION" --arg package_version "$VERSION" \
  --arg patches "$patch_digest" --arg locks "$dependency_locks_digest" \
  --arg rust "$RUST_TOOLCHAIN" --arg rustc "$ONE_KVM_RUSTC_COMMIT" --arg pnpm "$PNPM_VERSION" \
  --arg container "$ONE_KVM_ARMV7_OCI_IMAGE" --arg gcc "$ONE_KVM_ARMV7_GCC_VERSION" \
  --arg binutils "$ONE_KVM_ARMV7_BINUTILS_VERSION" --arg x264 "$ONE_KVM_X264_COMMIT" \
  --arg libvpx "$ONE_KVM_LIBVPX_COMMIT" --arg x265 "$ONE_KVM_X265_COMMIT" \
  --arg rkmpp "$ONE_KVM_RKMPP_COMMIT" --arg rkrga "$ONE_KVM_RKRGA_COMMIT" \
  --argjson software_codecs "$software_codecs" \
  --argjson epoch "$SOURCE_DATE_EPOCH" \
  '{schema:1,channel:"experimental",upstream_repository:$repository,upstream_ref:$ref,
    upstream_commit:$commit,one_kvm_version:$upstream_version,package_version:$package_version,
    patches_sha256:$patches,dependency_locks_sha256:$locks,rust_toolchain:$rust,rustc_commit:$rustc,
    pnpm_version:$pnpm,source_date_epoch:$epoch,build_container:$container,
    toolchain:{gcc:$gcc,binutils:$binutils},dependencies:{x264:$x264,libvpx:$libvpx,x265:$x265,rkmpp:$rkmpp,rkrga:$rkrga},
    platform:"WS1608/S805/Meson8b/armv7",codec:"h264_amlenc",amlenc_smoke_test_default:false,
    software_codecs:$software_codecs,
    hardware_encoder_tested:false,
    stable_channel_modified:false,redistribution:"local-test-only"}' >"$metadata"
(cd "$package_dir" && sha256sum usr/bin/one-kvm usr/lib/one-kvm/libvpcodec.so usr/lib/one-kvm/amlenc-m8-diag usr/share/doc/one-kvm/ws1608-amlenc-build.json >usr/share/doc/one-kvm/SHA256SUMS)
find "$package_dir" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
package_name="one-kvm_${VERSION}_armhf.deb"
dpkg-deb --root-owner-group -Zxz -z9 -b "$package_dir" "$OUTPUT_DIR/$package_name" >/dev/null
(cd "$ROOT_DIR" && node experimental/amlenc/scripts/verify-one-kvm-metadata.mjs "$metadata" "$CONFIG_FILE")
cp "$metadata" "$OUTPUT_DIR/$package_name.build.json"
(cd "$OUTPUT_DIR" && sha256sum "$package_name" >"$package_name.sha256")
echo "built $OUTPUT_DIR/one-kvm_${VERSION}_armhf.deb"
