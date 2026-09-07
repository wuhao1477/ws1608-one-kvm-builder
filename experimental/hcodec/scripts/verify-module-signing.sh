#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE=${1:?usage: verify-module-signing.sh CONFIG_FILE MODULE_DIR REPORT}
MODULE_DIR=${2:?usage: verify-module-signing.sh CONFIG_FILE MODULE_DIR REPORT}
REPORT=${3:?usage: verify-module-signing.sh CONFIG_FILE MODULE_DIR REPORT}
[[ -f "$CONFIG_FILE" && -d "$MODULE_DIR" ]] || { echo 'invalid module signing inputs' >&2; exit 1; }

grep -Fxq '# CONFIG_MODULE_SIG is not set' "$CONFIG_FILE" || {
  echo 'CONFIG_MODULE_SIG must match the disabled stable policy' >&2
  exit 1
}
module=$(find "$MODULE_DIR" -type f -name 'meson-venc.ko' -print -quit)
[[ -n "$module" ]] || { echo 'meson-venc.ko not found' >&2; exit 1; }
[[ -z "$(modinfo -F signer "$module")" ]] || { echo 'unexpected module signer' >&2; exit 1; }
[[ -z "$(modinfo -F sig_id "$module")" ]] || { echo 'unexpected module signature ID' >&2; exit 1; }

mkdir -p "$(dirname "$REPORT")"
printf '%s\n' '{"schema":1,"stable_policy":"disabled","candidate_policy":"disabled","meson_venc_signed":false}' >"$REPORT"
echo 'verified disabled module signing policy'
