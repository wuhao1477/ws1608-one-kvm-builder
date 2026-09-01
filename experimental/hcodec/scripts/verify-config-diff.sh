#!/usr/bin/env bash
set -Eeuo pipefail

BASE_CONFIG=${1:?usage: verify-config-diff.sh BASE_CONFIG CANDIDATE_CONFIG}
CANDIDATE_CONFIG=${2:?usage: verify-config-diff.sh BASE_CONFIG CANDIDATE_CONFIG}
[[ -f "$BASE_CONFIG" && ! -L "$BASE_CONFIG" ]] || { echo "invalid base config" >&2; exit 1; }
[[ -f "$CANDIDATE_CONFIG" && ! -L "$CANDIDATE_CONFIG" ]] || { echo "invalid candidate config" >&2; exit 1; }

grep -Fxq 'CONFIG_VIDEO_MESON_VENC=m' "$CANDIDATE_CONFIG" || {
  echo 'CONFIG_VIDEO_MESON_VENC must be m' >&2
  exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/hcodec-config-diff.XXXXXX")
trap 'rm -rf "$work"' EXIT
normalize() {
  grep -E '^(CONFIG_[A-Z0-9_]+=|# CONFIG_[A-Z0-9_]+ is not set$)' "$1" |
    grep -v '^CONFIG_VIDEO_MESON_VENC=' |
    grep -v '^# CONFIG_VIDEO_MESON_VENC is not set$' |
    LC_ALL=C sort
}
normalize "$BASE_CONFIG" >"$work/base"
normalize "$CANDIDATE_CONFIG" >"$work/candidate"
cmp -s "$work/base" "$work/candidate" || {
  diff -u "$work/base" "$work/candidate" >&2 || true
  echo 'candidate config differs outside CONFIG_VIDEO_MESON_VENC' >&2
  exit 1
}

for expected in \
  CONFIG_MODULES=y \
  CONFIG_FW_LOADER=y \
  CONFIG_MEDIA_SUPPORT=m \
  CONFIG_VIDEO_DEV=m \
  CONFIG_V4L2_MEM2MEM_DEV=m \
  CONFIG_VIDEOBUF2_DMA_CONTIG=m \
  CONFIG_MESON_CANVAS=y; do
  grep -Fxq "$expected" "$CANDIDATE_CONFIG" || {
    echo "required candidate state missing: $expected" >&2
    exit 1
  }
done

echo 'verified HCODEC config diff'
