#!/usr/bin/env bash
set -Eeuo pipefail

PATCH_DIR=${1:?usage: patch-digest.sh PATCH_DIR}
[[ -d "$PATCH_DIR" && ! -L "$PATCH_DIR" ]] || { echo "invalid patch directory" >&2; exit 1; }
(
  cd "$PATCH_DIR"
  sha256sum ./*.patch | sed 's#  \./#  #' | LC_ALL=C sort | sha256sum | cut -d' ' -f1
)
