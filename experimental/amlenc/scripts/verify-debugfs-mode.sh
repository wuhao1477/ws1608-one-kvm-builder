#!/usr/bin/env bash
set -euo pipefail

mode=${1:?expected mode is required}
grep -Eq "(^|[[:space:]])Mode:[[:space:]]+${mode}([[:space:]]|$)"
