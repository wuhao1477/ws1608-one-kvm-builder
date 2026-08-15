#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 3 ]] || {
  echo "usage: $0 MODE SOURCE DESTINATION" >&2
  exit 64
}

mode=$1
source_path=$2
destination_path=$3

mkdir -p "$(dirname "$destination_path")"
install -m "$mode" "$source_path" "$destination_path"
