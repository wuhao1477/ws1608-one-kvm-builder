#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=${1:?usage: verify-kernel-source-diff.sh SOURCE_DIR}
EXPECTED_PATHS=$'arch/arm/boot/dts/meson8b_odroidc.dts\ndrivers/amlogic/amports/encoder.c'

git -C "$SOURCE_DIR" diff --check

changed_paths=$(
  git -C "$SOURCE_DIR" status --porcelain=v1 --untracked-files=all |
    sed -E 's/^...//'
)

if [[ "$changed_paths" != "$EXPECTED_PATHS" ]]; then
  printf 'unexpected kernel source changes:\n' >&2
  git -C "$SOURCE_DIR" status --short --untracked-files=all >&2
  exit 1
fi
