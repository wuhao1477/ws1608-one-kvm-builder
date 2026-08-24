#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
PACKAGE=${1:?usage: verify-one-kvm-software-codecs.sh PACKAGE.deb}
source "$ROOT_DIR/experimental/amlenc/config/sources.env"

fail() { echo "One-KVM software codec verification failed: $*" >&2; exit 1; }
for command in basename docker dpkg-deb jq mktemp realpath; do command -v "$command" >/dev/null || fail "missing command: $command"; done
[[ -f "$PACKAGE" && ! -L "$PACKAGE" ]] || fail "invalid package"
package_path=$(realpath -e -- "$PACKAGE")
package_dir=$(dirname "$package_path")
package_name=$(basename "$package_path")
[[ "$package_name" =~ ^one-kvm_[A-Za-z0-9.+-]+_armhf\.deb$ ]] || fail "unsafe package name"
[[ "$(dpkg-deb -f "$package_path" Architecture)" == armhf ]] || fail "package architecture is not armhf"
runtime_dir=$(mktemp -d "${TMPDIR:-/tmp}/ws1608-one-kvm-codecs.XXXXXX")
trap 'rm -rf "$runtime_dir"' EXIT
dpkg-deb -x "$package_path" "$runtime_dir/root"

set +e
result=$(docker run --rm --platform linux/arm/v7 \
  -v "$runtime_dir/root:/opt/one-kvm:ro" "$BULLSEYE_ARMV7_OCI_IMAGE" sh -euc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >&2
    apt-get install -y --no-install-recommends ca-certificates libasound2 libdrm2 libudev1 libv4l-0 libva2 >&2
    exec /opt/one-kvm/usr/bin/one-kvm codec self-check --backend software --json
  ')
codec_status=$?
set -e

if [[ -z "$result" ]]; then
  fail "software self-check produced no JSON (exit $codec_status)"
fi
if [[ "$codec_status" -ne 0 ]]; then
  printf '%s\n' "$result" >&2
  fail "software self-check command failed (exit $codec_status)"
fi

jq -e '
  .backend == "software" and
  (.rows | length) == 1 and
  .rows[0].resolution_id == "320p" and .rows[0].width == 320 and .rows[0].height == 240 and
  ([.rows[0].cells[].codec_id] | sort) == ["h264", "h265", "vp8", "vp9"] and
  all(.rows[0].cells[];
    .backend == "software" and .ok == true and .submitted_frames == 10 and .decoded_frames == 10 and
    ((.codec_id == "h264" and .encoder == "libx264" and .decoder == "h264") or
     (.codec_id == "h265" and .encoder == "libx265" and .decoder == "hevc") or
     (.codec_id == "vp8" and .encoder == "libvpx_vp8" and .decoder == "vp8") or
     (.codec_id == "vp9" and .encoder == "libvpx_vp9" and .decoder == "vp9")))
' <<<"$result" >/dev/null || {
  printf '%s\n' "$result" >&2
  fail "software self-check result"
}
printf '%s\n' "$result"
