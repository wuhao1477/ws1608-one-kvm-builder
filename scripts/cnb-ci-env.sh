#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

ensure_cnb_cli() {
  if command -v cnb >/dev/null 2>&1; then
    return
  fi
  command -v npm >/dev/null 2>&1 || { echo 'npm is required to install cnb CLI' >&2; exit 1; }
  local prefix=${CNB_CLI_PREFIX:-${CNB_BUILD_WORKSPACE:-$ROOT_DIR}/.cnb-tools}
  mkdir -p "$prefix"
  npm install --prefix "$prefix" --no-fund --no-audit --silent @cnbcool/cnb-cli
  export PATH="$prefix/bin:$PATH"
  command -v cnb >/dev/null 2>&1 || { echo 'cnb CLI installation failed' >&2; exit 1; }
}

ensure_cnb_cli
: "${CNB_COMMIT:=$(git -C "$ROOT_DIR" rev-parse HEAD)}"
: "${CNB_REPO_SLUG:=wuhao1477/ws1608-one-kvm-builder}"
: "${CNB_BRANCH:=main}"
: "${CNB_BUILD_ID:=local}"
: "${CNB_BUILD_ATTEMPT:=1}"

if [[ "${CNB_BUILD_ID}" =~ ^[0-9]+$ ]]; then
  CNB_BUILD_NUMBER=$CNB_BUILD_ID
else
  CNB_BUILD_NUMBER=$(printf '%s' "$CNB_BUILD_ID" | cksum | awk '{print $1 + 1}')
fi

export CNB_BUILD_NUMBER
export GITHUB_SHA=$CNB_COMMIT
export GITHUB_REPOSITORY=$CNB_REPO_SLUG
export GITHUB_WORKSPACE=${CNB_BUILD_WORKSPACE:-$ROOT_DIR}
export GITHUB_RUN_ID=$CNB_BUILD_ID
export GITHUB_RUN_ATTEMPT=$CNB_BUILD_ATTEMPT
export GITHUB_RUN_NUMBER=$CNB_BUILD_NUMBER
export GITHUB_REF="refs/heads/$CNB_BRANCH"
export GITHUB_REF_NAME=$CNB_BRANCH
export GITHUB_EVENT_NAME=${CNB_EVENT:-push}
