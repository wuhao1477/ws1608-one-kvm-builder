#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/config/tool-versions.env"
TOOLS_DIR=${TOOLS_DIR:-$ROOT_DIR/.tools}
SOURCE_DIR="$TOOLS_DIR/AmlImg-src"
mkdir -p "$TOOLS_DIR"
rm -rf "$SOURCE_DIR"
git init -q "$SOURCE_DIR"
git -C "$SOURCE_DIR" remote add origin "$AMLIMG_REPOSITORY"
git -C "$SOURCE_DIR" fetch -q --depth=1 origin "$AMLIMG_COMMIT"
git -C "$SOURCE_DIR" checkout -q --detach FETCH_HEAD
(
  cd "$SOURCE_DIR"
  CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=$AMLIMG_COMMIT" -o "$TOOLS_DIR/AmlImg" .
)
printf '%s\n' "$TOOLS_DIR/AmlImg"
