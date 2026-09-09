#!/usr/bin/env bash
set -Eeuo pipefail

RESULTS_DIR=${1:?usage: capture-stability-probe.sh RESULTS_DIR SMOKE_BINARY DEVICE OUTPUT.h264 [SMOKE_ARGS...]}
SMOKE_BINARY=${2:?usage: capture-stability-probe.sh RESULTS_DIR SMOKE_BINARY DEVICE OUTPUT.h264 [SMOKE_ARGS...]}
DEVICE=${3:?usage: capture-stability-probe.sh RESULTS_DIR SMOKE_BINARY DEVICE OUTPUT.h264 [SMOKE_ARGS...]}
OUTPUT=${4:?usage: capture-stability-probe.sh RESULTS_DIR SMOKE_BINARY DEVICE OUTPUT.h264 [SMOKE_ARGS...]}
shift 4

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CAPTURE_PROBE="$SCRIPT_DIR/capture-probe.sh"
[[ -x "$SMOKE_BINARY" ]] || { echo "smoke binary is not executable: $SMOKE_BINARY" >&2; exit 1; }
[[ -x "$CAPTURE_PROBE" ]] || { echo "capture probe is not executable: $CAPTURE_PROBE" >&2; exit 1; }
mkdir -p "$RESULTS_DIR"
[[ -d "$RESULTS_DIR" && ! -L "$RESULTS_DIR" ]] || { echo 'invalid results directory' >&2; exit 1; }

probe_status=0
if "$CAPTURE_PROBE" "$RESULTS_DIR" "$SMOKE_BINARY" "$DEVICE" "$OUTPUT" "$@"; then
  probe_status=0
else
  probe_status=$?
fi
printf '%s\n' "$probe_status" >"$RESULTS_DIR/exit-status"

health_follower_pid=''
cleanup_health_trace() {
  local status=$?

  trap - EXIT
  if [[ -n "$health_follower_pid" ]]; then
    kill "$health_follower_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$health_follower_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$health_follower_pid" 2>/dev/null || true
    wait "$health_follower_pid" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup_health_trace EXIT

dmesg --follow-new --time-format iso >"$RESULTS_DIR/kernel.health.log" 2>&1 &
health_follower_pid=$!

for ((second = 1; second <= 60; second++)); do
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  uptime=$(cut -d. -f1 /proc/uptime 2>/dev/null || printf 'unknown')
  operstate=$(cat /sys/class/net/eth0/operstate 2>/dev/null || printf 'unknown')
  carrier=$(cat /sys/class/net/eth0/carrier 2>/dev/null || printf 'unknown')
  ip_address=$(ip -brief addr show eth0 2>/dev/null | tr '\n' ' ' || true)
  printf '%s second=%s uptime=%s eth0=%s carrier=%s ip=%s\n' \
    "$timestamp" "$second" "$uptime" "$operstate" "$carrier" "$ip_address" \
    >>"$RESULTS_DIR/health.log"
  sync
  sleep 1
done

dmesg --time-format iso >"$RESULTS_DIR/kernel.health.after.log" 2>&1 || true
sync

exit "$probe_status"
