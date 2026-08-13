#!/usr/bin/env bash
set -euo pipefail

[[ $# -gt 0 ]] || { echo "at least one package is required" >&2; exit 64; }
apt-get -o Acquire::Retries=5 update
apt-get -o Acquire::Retries=5 install -y --no-install-recommends "$@"
