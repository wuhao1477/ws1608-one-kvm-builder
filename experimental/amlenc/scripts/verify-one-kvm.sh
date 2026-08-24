#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
PACKAGE=${1:?usage: verify-one-kvm.sh PACKAGE.deb}
fail() { echo "One-KVM package verification failed: $*" >&2; exit 1; }
[[ -f "$PACKAGE" ]] || fail "package is missing: $PACKAGE"
for command in dpkg-deb readelf jq sha256sum; do
  command -v "$command" >/dev/null || fail "missing command: $command"
done

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
[[ "$package_name" == one-kvm ]] || fail "unexpected package name: $package_name"
[[ "$package_version" =~ ^0\.2\.6\+ws1608amlenc\. ]] || fail "unexpected package version: $package_version"
[[ "$package_architecture" == armhf ]] || fail "unexpected package architecture: $package_architecture"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
dpkg-deb -x "$PACKAGE" "$tmp" || fail "could not extract package"
binary="$tmp/usr/bin/one-kvm"
[[ -s "$binary" ]] || fail "One-KVM executable is missing"
program_headers=$(readelf -l "$binary") || fail "could not read ELF program headers"
elf_header=$(readelf -h "$binary") || fail "could not read ELF header"
elf_comment=$(readelf -p .comment "$binary") || fail "could not read compiler comments"
grep -q '/lib/ld-linux-armhf.so.3' <<<"$program_headers" || fail "ELF interpreter is not armhf"
grep -q 'Class:.*ELF32' <<<"$elf_header" || fail "ELF class is not 32-bit"
grep -q 'Machine:.*ARM' <<<"$elf_header" || fail "ELF machine is not ARM"
grep -Fq "GCC: (Debian $ONE_KVM_ARMV7_GCC_VERSION" <<<"$elf_comment" || fail "GCC version is not pinned"
grep -Fq "rustc version $ONE_KVM_RUST_TOOLCHAIN (${ONE_KVM_RUSTC_COMMIT:0:9}" <<<"$elf_comment" || fail "Rust compiler version is not pinned"
[[ -s "$tmp/usr/lib/one-kvm/libvpcodec.so" ]] || fail "libvpcodec.so is missing"
[[ -s "$tmp/usr/lib/one-kvm/amlenc-m8-diag" ]] || fail "amlenc-m8-diag is missing"
if ! jq -e \
  --arg upstream_commit "$ONE_KVM_COMMIT" \
  --arg patches_sha256 "$patches_sha256" \
  --arg dependency_locks_sha256 "$dependency_locks_sha256" \
  '.schema == 1
    and .upstream_commit == $upstream_commit
    and .patches_sha256 == $patches_sha256
    and .dependency_locks_sha256 == $dependency_locks_sha256
    and .rust_toolchain == "1.97.1"
    and .pnpm_version == "10.15.0"
    and .amlenc_smoke_test_default == false' \
  "$tmp/usr/share/doc/one-kvm/ws1608-amlenc-build.json" >/dev/null; then
  fail "build provenance metadata does not match source locks"
fi
if ! jq -e '
  .hardware_encoder_tested == false and .stable_channel_modified == false and .codec == "h264_amlenc" and
  .software_codecs == [
    {id:"h264",encoder:"libx264",decoder:"h264",hardware:false},
    {id:"h265",encoder:"libx265",decoder:"hevc",hardware:false},
    {id:"vp8",encoder:"libvpx_vp8",decoder:"vp8",hardware:false},
    {id:"vp9",encoder:"libvpx_vp9",decoder:"vp9",hardware:false}
  ]
' "$tmp/usr/share/doc/one-kvm/ws1608-amlenc-build.json" >/dev/null; then
  fail "hardware encoder metadata contract failed"
fi
if ! node "$ROOT_DIR/experimental/amlenc/scripts/verify-one-kvm-metadata.mjs" \
  "$tmp/usr/share/doc/one-kvm/ws1608-amlenc-build.json" \
  "$ROOT_DIR/experimental/amlenc/config/sources.env"; then
  fail "immutable metadata verification failed"
fi
if ! (cd "$tmp" && sha256sum --check usr/share/doc/one-kvm/SHA256SUMS); then
  fail "package file checksums failed"
fi
echo "verified One-KVM WS1608 AMLENC armhf package"
