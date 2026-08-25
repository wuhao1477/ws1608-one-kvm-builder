#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
LIMITS_FILE=${AMLENC_HARDWARE_LIMITS:-/usr/local/share/ws1608-amlenc/hardware-limits.json}

fail() {
  echo "hardware gate failed: $*" >&2
  exit 1
}

redact() {
  sed -E \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/[REDACTED_IPV4]/g' \
    -e 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/[REDACTED_MAC]/g' \
    -e 's/([Ss][Ee][Rr][Ii][Aa][Ll][=:])[[:graph:]]+/\1[REDACTED_SERIAL]/g' \
    -e 's/([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][=:])[[:graph:]]+/\1[REDACTED_SECRET]/g' \
    -e 's/([Tt][Oo][Kk][Ee][Nn][=:])[[:graph:]]+/\1[REDACTED_SECRET]/g'
}

usage() {
  echo "usage: $0 --probe ID --input STREAM --output-dir DIR [--kernel-log FILE]" >&2
  exit 2
}

probe_id=
input=
output_dir=
kernel_log=
while (($#)); do
  case "$1" in
    --probe) probe_id=${2:-}; shift 2 ;;
    --input) input=${2:-}; shift 2 ;;
    --output-dir) output_dir=${2:-}; shift 2 ;;
    --kernel-log) kernel_log=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$probe_id" && -n "$input" && -n "$output_dir" ]] || usage
[[ -f "$input" && -s "$input" ]] || fail "input stream is missing or empty"
[[ -f "$LIMITS_FILE" ]] || fail "hardware limits are missing"
[[ ! -L "$output_dir" ]] || fail "output directory must not be a symbolic link"
if [[ -d "$output_dir" ]]; then
  [[ -z "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
    fail "output directory must be empty"
elif [[ -e "$output_dir" ]]; then
  fail "output directory must be a directory"
fi
for command in ffprobe ffmpeg jq sha256sum; do
  command -v "$command" >/dev/null || fail "required command is missing: $command"
done

probe=$(jq -ce --arg id "$probe_id" '.probes[] | select(.id == $id)' "$LIMITS_FILE") ||
  fail "unknown fixed probe: $probe_id"
width=$(jq -r '.width' <<<"$probe")
height=$(jq -r '.height' <<<"$probe")
fps=$(jq -r '.fps' <<<"$probe")
frames=$(jq -r '.frames' <<<"$probe")
bitrate=$(jq -r '.bitrate' <<<"$probe")
duration=$(jq -r '.duration_seconds' <<<"$probe")

mkdir -p "$output_dir"
ffprobe_json="$output_dir/ffprobe.json"
decode_log="$output_dir/decode.log"
headers_log="$output_dir/headers.log"
kernel_errors_log="$output_dir/kernel-errors.log"
report="$output_dir/validation.json"

ffprobe -v error -framerate "$fps" -select_streams v:0 -count_frames \
  -show_entries stream=codec_name,width,height,r_frame_rate,avg_frame_rate,nb_read_frames \
  -of json "$input" >"$ffprobe_json" || fail "ffprobe could not parse stream"

codec=$(jq -r '.streams[0].codec_name // empty' "$ffprobe_json")
actual_width=$(jq -r '.streams[0].width // 0' "$ffprobe_json")
actual_height=$(jq -r '.streams[0].height // 0' "$ffprobe_json")
actual_frames=$(jq -r '.streams[0].nb_read_frames // 0' "$ffprobe_json")
rate=$(jq -r '
  .streams[0] as $stream |
  ($stream.avg_frame_rate // "") as $avg |
  if ($avg | test("^[1-9][0-9]*/[1-9][0-9]*$")) then $avg
  else ($stream.r_frame_rate // empty)
  end
' "$ffprobe_json")
actual_fps=$(awk -v rate="$rate" 'BEGIN { split(rate, p, "/"); if (p[2] + 0 == 0) exit 1; printf "%.6g", p[1] / p[2] }') ||
  fail "invalid frame rate"

[[ "$codec" == h264 ]] || fail "codec is not H.264"
[[ "$actual_width" == "$width" && "$actual_height" == "$height" ]] ||
  fail "resolution does not match fixed probe"
[[ "$actual_frames" == "$frames" ]] || fail "frame count does not match fixed probe"
awk -v actual="$actual_fps" -v expected="$fps" 'BEGIN { d=actual-expected; if (d<0) d=-d; exit(d > 0.001) }' ||
  fail "frame rate does not match fixed probe"

if ! ffmpeg -v error -framerate "$fps" -i "$input" -map 0:v:0 -f null - 2>"$decode_log"; then
  fail "decode validation failed"
fi
[[ ! -s "$decode_log" ]] || fail "decode validation reported errors"

set +o pipefail
ffmpeg -v trace -framerate "$fps" -i "$input" -map 0:v:0 -c copy -bsf:v trace_headers -f null - \
  2>&1 >/dev/null | awk '
    /Sequence Parameter Set|Picture Parameter Set|(^|[^A-Za-z])IDR([^A-Za-z]|$)|nal_unit_type[^0-9]*5/ {
      print
      if (/Sequence Parameter Set/) sps=1
      if (/Picture Parameter Set/) pps=1
      if (/(^|[^A-Za-z])IDR([^A-Za-z]|$)|nal_unit_type[^0-9]*5/) idr=1
      if (sps && pps && idr) exit 0
    }
  ' >"$headers_log"
header_status=("${PIPESTATUS[@]}")
set -o pipefail
[[ ${header_status[0]} -eq 0 || ${header_status[0]} -eq 141 ]] ||
  fail "Annex-B header inspection failed"
grep -qi 'Sequence Parameter Set' "$headers_log" || fail "SPS is missing"
grep -qi 'Picture Parameter Set' "$headers_log" || fail "PPS is missing"
grep -Eqi '(^|[^A-Za-z])IDR([^A-Za-z]|$)|nal_unit_type[^0-9]*5' "$headers_log" || fail "IDR is missing"

if [[ -n "$kernel_log" ]]; then
  [[ -f "$kernel_log" ]] || fail "kernel log is missing"
  kernel_source=$kernel_log
else
  kernel_source="$output_dir/.dmesg"
  dmesg >"$kernel_source" 2>/dev/null || fail "cannot read kernel log; pass --kernel-log"
fi
grep -Ei 'amvenc|encoder|codec_mm|cma|ion|oops|panic|timeout|corrupt' "$kernel_source" \
  | redact \
  >"$output_dir/kernel-encoder.log" || :
grep -Ei 'kernel panic|\boops\b|cma.*(fail|error)|codec_mm.*(fail|error)|amvenc.*timeout|encoder.*timeout|corrupt stream' \
  "$kernel_source" | redact >"$kernel_errors_log" || :
kernel_errors=$(wc -l <"$kernel_errors_log" | tr -d ' ')
[[ "$kernel_errors" == 0 ]] || fail "kernel encoder fault detected"

stream_sha256=$(sha256sum "$input" | awk '{print $1}')
jq -n \
  --arg probe "$probe_id" --arg codec "$codec" --arg sha "$stream_sha256" \
  --argjson width "$width" --argjson height "$height" --argjson fps "$fps" \
  --argjson frames "$frames" --argjson bitrate "$bitrate" --argjson duration "$duration" \
  --argjson actual_width "$actual_width" --argjson actual_height "$actual_height" \
  --argjson actual_fps "$actual_fps" --argjson actual_frames "$actual_frames" \
  --argjson kernel_errors "$kernel_errors" '
  {
    schema: 1, probe: $probe, status: "passed",
    expected: {width: $width, height: $height, fps: $fps, frames: $frames,
      bitrate: $bitrate, duration_seconds: $duration},
    observed: {codec: $codec, width: $actual_width, height: $actual_height,
      fps: $actual_fps, frames: $actual_frames,
      duration_seconds: ($actual_frames / $actual_fps)},
    annex_b: {sps: true, pps: true, idr: true},
    decode_errors: 0, kernel_errors: $kernel_errors, stream_sha256: $sha
  }' >"$report"

rm -f "$output_dir/.dmesg" "$output_dir/SHA256SUMS"
(cd "$output_dir" && LC_ALL=C find . -maxdepth 1 -type f ! -name SHA256SUMS -print \
  | sed 's#^./##' | LC_ALL=C sort | xargs sha256sum >SHA256SUMS)
echo "hardware gate passed: $probe_id"
