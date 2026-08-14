#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
PACKAGE=${1:?usage: verify-one-kvm.sh PACKAGE.deb}
[[ -f "$PACKAGE" ]] || { echo "package is missing: $PACKAGE" >&2; exit 1; }
for command in dpkg-deb readelf jq sha256sum; do command -v "$command" >/dev/null || exit 1; done

set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/experimental/amlenc/config/sources.env"
set +a
patches_sha256=$("$ROOT_DIR/experimental/amlenc/scripts/one-kvm-patch-digest.sh" \
  "$ROOT_DIR/experimental/amlenc/patches/one-kvm")
dependency_locks_sha256=$(
  cd "$ROOT_DIR/experimental/amlenc/locks/one-kvm"
  sha256sum Cargo.lock pnpm-lock.yaml | sha256sum | awk '{print $1}'
)

package_name=$(dpkg-deb -f "$PACKAGE" Package)
package_version=$(dpkg-deb -f "$PACKAGE" Version)
package_architecture=$(dpkg-deb -f "$PACKAGE" Architecture)
[[ "$package_name" == one-kvm ]]
[[ "$package_version" =~ ^0\.2\.6\+ws1608amlenc\. ]]
[[ "$package_architecture" == armhf ]]

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dpkg-deb -x "$PACKAGE" "$tmp"
readelf -l "$tmp/usr/bin/one-kvm" | grep -q '/lib/ld-linux-armhf.so.3'
readelf -h "$tmp/usr/bin/one-kvm" | grep -q 'Class:.*ELF32'
readelf -h "$tmp/usr/bin/one-kvm" | grep -q 'Machine:.*ARM'
readelf -p .comment "$tmp/usr/bin/one-kvm" | grep -Fq "GCC: (Debian $ONE_KVM_ARMV7_GCC_VERSION"
readelf -p .comment "$tmp/usr/bin/one-kvm" | grep -Fq "rustc version $ONE_KVM_RUST_TOOLCHAIN (${ONE_KVM_RUSTC_COMMIT:0:9}"
[[ -s "$tmp/usr/lib/one-kvm/libvpcodec.so" && -s "$tmp/usr/lib/one-kvm/amlenc-m8-diag" ]]
jq -e \
  --arg upstream_commit "$ONE_KVM_COMMIT" \
  --arg patches_sha256 "$patches_sha256" \
  --arg dependency_locks_sha256 "$dependency_locks_sha256" \
  '.schema == 1
    and .upstream_commit == $upstream_commit
    and .patches_sha256 == $patches_sha256
    and .dependency_locks_sha256 == $dependency_locks_sha256
    and .rust_toolchain == "1.97.1"
    and .pnpm_version == "10.15.0"' \
  "$tmp/usr/share/doc/one-kvm/ws1608-amlenc-build.json" >/dev/null
jq -e '.hardware_encoder_tested == false and .stable_channel_modified == false and .codec == "h264_amlenc"' "$tmp/usr/share/doc/one-kvm/ws1608-amlenc-build.json" >/dev/null
node "$ROOT_DIR/experimental/amlenc/scripts/verify-one-kvm-metadata.mjs" \
  "$tmp/usr/share/doc/one-kvm/ws1608-amlenc-build.json" \
  "$ROOT_DIR/experimental/amlenc/config/sources.env"
(cd "$tmp" && sha256sum --check usr/share/doc/one-kvm/SHA256SUMS)
echo "verified One-KVM WS1608 AMLENC armhf package"
