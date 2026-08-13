#!/usr/bin/env bash
set -euo pipefail

archive=${1:?archive path is required}
rootfs=${2:-/}
tar --numeric-owner --xattrs --acls -cpf "$archive" \
  --exclude=./work --exclude=./repo --exclude=./build-tools --exclude=./proc --exclude=./sys \
  --exclude=./dev --exclude=./run -C "$rootfs" .
