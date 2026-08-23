#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
source "$ROOT_DIR/experimental/amlenc/config/sources.env"
PATCH="$ROOT_DIR/experimental/amlenc/patches/stable-kernel/0001-amlenc-6.12-research-boundary.patch"

fail() { echo "stable kernel boundary verification failed: $*" >&2; exit 1; }
[[ "$STABLE_KERNEL_VERSION" == 6.12.28-current-meson ]] || fail "unexpected stable kernel"
[[ "$STABLE_KERNEL_AMLENC_STATUS" == research-only ]] || fail "unexpected driver status"
[[ -f "$PATCH" && ! -L "$PATCH" ]] || fail "research patch missing"
git apply --stat "$PATCH" >/dev/null || fail "invalid patch format"
grep -Fq 'config VIDEO_MESON8B_AMLENC_RESEARCH' "$PATCH" || fail "Kconfig symbol missing"
grep -Fq 'default n' "$PATCH" || fail "research driver must default to disabled"
grep -Fq 'return -ENODEV' "$PATCH" || fail "probe must remain non-functional"
grep -Fq 'amlogic,meson8b-amvenc' "$PATCH" || fail "compatible string missing"
grep -Fq 'amvenc_avc' "$PATCH" || fail "vendor ABI node is undocumented"
if grep -Eq '^diff --git a/arch/arm/boot/dts|HDMI|MMC|USB' "$PATCH"; then
  fail "research patch changes stable DTB, HDMI, eMMC or USB paths"
fi
echo "verified disabled $STABLE_KERNEL_VERSION AMLENC research boundary"
