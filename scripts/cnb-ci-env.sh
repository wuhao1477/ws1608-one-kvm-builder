#!/usr/bin/env bash
set -Eeuo pipefail

ensure_node() {
  if command -v node >/dev/null 2>&1; then
    return
  fi
  command -v curl >/dev/null 2>&1 || { echo 'curl is required to install Node.js' >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo 'tar is required to install Node.js' >&2; exit 1; }
  local version=${CNB_NODE_VERSION:-22.21.0}
  local platform=linux-x64
  local prefix=${CNB_NODE_PREFIX:-${CNB_BUILD_WORKSPACE:-$ROOT_DIR}/.cnb-tools/node-v$version-$platform}
  local archive="$prefix.tar.gz"
  mkdir -p "$(dirname "$prefix")"
  if [[ ! -x "$prefix/bin/node" ]]; then
    curl --fail --silent --show-error --location --retry 5 --retry-all-errors \
      "https://nodejs.org/dist/v$version/node-v$version-$platform.tar.gz" -o "$archive"
    tar -xzf "$archive" -C "$(dirname "$prefix")"
    rm -f "$archive"
  fi
  export PATH="$prefix/bin:$PATH"
  command -v node >/dev/null 2>&1 || { echo 'Node.js installation failed' >&2; exit 1; }
}

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    return
  fi
  command -v curl >/dev/null 2>&1 || { echo 'curl is required to install Go' >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo 'tar is required to install Go' >&2; exit 1; }
  command -v sha256sum >/dev/null 2>&1 || { echo 'sha256sum is required to verify Go' >&2; exit 1; }
  local version=${CNB_GO_VERSION:-1.24.13}
  local platform=linux-amd64
  local prefix=${CNB_GO_PREFIX:-${CNB_BUILD_WORKSPACE:-$ROOT_DIR}/.cnb-tools/go}
  local archive="$prefix.tar.gz"
  local digest=1fc94b57134d51669c72173ad5d49fd62afb0f1db9bf3f798fd98ee423f8d730
  mkdir -p "$(dirname "$prefix")"
  if [[ ! -x "$prefix/bin/go" ]]; then
    curl --fail --silent --show-error --location --retry 5 --retry-all-errors \
      "https://go.dev/dl/go$version.$platform.tar.gz" -o "$archive"
    printf '%s  %s\n' "$digest" "$archive" | sha256sum --check
    tar -xzf "$archive" -C "$(dirname "$prefix")"
    rm -f "$archive"
  fi
  export PATH="$prefix/bin:$PATH"
  command -v go >/dev/null 2>&1 || { echo 'Go installation failed' >&2; exit 1; }
}

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

ensure_cnb_cli() {
  if command -v cnb >/dev/null 2>&1; then
    return
  fi
  export PATH="$ROOT_DIR/scripts:$PATH"
  command -v cnb >/dev/null 2>&1 || { echo 'cnb CLI compatibility entrypoint is missing' >&2; exit 1; }
}

ensure_cnb_cli
ensure_node
ensure_go
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
