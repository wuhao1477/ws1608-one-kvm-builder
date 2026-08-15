#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=${1:?usage: prepare-one-kvm-cross-image.sh SOURCE_DIR IMAGE}
IMAGE=${2:?usage: prepare-one-kvm-cross-image.sh SOURCE_DIR IMAGE}
DOCKERFILE="$SOURCE_DIR/build/cross/Dockerfile.armv7"
CROSS_CONFIG="$SOURCE_DIR/Cross.toml"

[[ -d "$SOURCE_DIR" && -f "$DOCKERFILE" && -f "$CROSS_CONFIG" ]]
command -v docker >/dev/null
command -v node >/dev/null

DOCKER_BUILDKIT=1 docker build \
  --platform linux/amd64 \
  --progress=plain \
  --tag "$IMAGE" \
  --file "$DOCKERFILE" \
  "$SOURCE_DIR"

export CROSS_CONFIG
export CROSS_IMAGE="$IMAGE"
node <<'NODE'
const fs = require('node:fs');

const path = process.env.CROSS_CONFIG;
const image = process.env.CROSS_IMAGE;
const source = fs.readFileSync(path, 'utf8');
const target = '[target.armv7-unknown-linux-gnueabihf]';
const start = source.indexOf(target);
if (start < 0) throw new Error(`missing ${target}`);
const end = source.indexOf('\n[', start + target.length);
const stop = end < 0 ? source.length : end;
const block = source.slice(start, stop)
  .replace(/^dockerfile\s*=.*\n/m, '')
  .replace(/^image\s*=.*\n/m, '')
  + `image = "${image}"\n`;
fs.writeFileSync(path, `${source.slice(0, start)}${block}${source.slice(stop)}`);
NODE

echo "prepared ARMv7 Cross image $IMAGE"
