#!/usr/bin/env bash
set -euo pipefail

PATCH_DIR=${1:?usage: one-kvm-patch-digest.sh PATCH_DIR}
(
  cd "$PATCH_DIR"
  sha256sum ./*.patch | sed 's#  \./#  #' | LC_ALL=C sort | sha256sum | cut -d' ' -f1
)
