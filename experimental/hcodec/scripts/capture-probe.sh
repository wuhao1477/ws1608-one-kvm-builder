#!/usr/bin/env bash
set -Eeuo pipefail

RESULTS_DIR=${1:?usage: capture-probe.sh RESULTS_DIR SMOKE_BINARY DEVICE OUTPUT.h264 [SMOKE_ARGS...]}
SMOKE_BINARY=${2:?usage: capture-probe.sh RESULTS_DIR SMOKE_BINARY DEVICE OUTPUT.h264 [SMOKE_ARGS...]}
DEVICE=${3:?usage: capture-probe.sh RESULTS_DIR SMOKE_BINARY DEVICE OUTPUT.h264 [SMOKE_ARGS...]}
OUTPUT=${4:?usage: capture-probe.sh RESULTS_DIR SMOKE_BINARY DEVICE OUTPUT.h264 [SMOKE_ARGS...]}
shift 4

[[ -x "$SMOKE_BINARY" ]] || { echo "smoke binary is not executable: $SMOKE_BINARY" >&2; exit 1; }
mkdir -p "$RESULTS_DIR"
[[ -d "$RESULTS_DIR" && ! -L "$RESULTS_DIR" ]] || { echo 'invalid results directory' >&2; exit 1; }

follower_pid=''
finalize() {
  local status=$?

  trap - EXIT
  if [[ -n "$follower_pid" ]]; then
    kill "$follower_pid" 2>/dev/null || true
    wait "$follower_pid" 2>/dev/null || true
  fi
  dmesg --time-format iso >"$RESULTS_DIR/kernel.after.log" 2>&1 || true
  printf '%s\n' "$status" >"$RESULTS_DIR/exit-status"
  sync
  exit "$status"
}
trap finalize EXIT

printf '%q ' "$SMOKE_BINARY" "$DEVICE" "$OUTPUT" "$@" >"$RESULTS_DIR/command.txt"
printf '\n' >>"$RESULTS_DIR/command.txt"
dmesg --time-format iso >"$RESULTS_DIR/kernel.before.log"
dmesg --follow-new --time-format iso >"$RESULTS_DIR/kernel.live.log" 2>&1 &
follower_pid=$!
sync
"$SMOKE_BINARY" "$DEVICE" "$OUTPUT" "$@" \
  >"$RESULTS_DIR/probe.stdout.log" 2>"$RESULTS_DIR/probe.stderr.log"
