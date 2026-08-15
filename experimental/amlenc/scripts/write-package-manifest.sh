#!/usr/bin/env bash
set -euo pipefail

output=${1:?output path is required}
dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' | LC_ALL=C sort >"$output"
[[ -s "$output" ]] || {
  echo "package manifest is empty" >&2
  exit 1
}
