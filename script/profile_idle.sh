#!/usr/bin/env bash
set -euo pipefail

APP_NAME="YuanGUI"
DURATION="${1:-60}"
PID="${2:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${3:-$ROOT_DIR/dist/performance-latest.txt}"

if ! [[ "$DURATION" =~ ^[1-9][0-9]*$ ]]; then
  echo "duration must be a positive integer" >&2
  exit 2
fi

if [[ -z "$PID" ]]; then
  PID="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
fi
if [[ -z "$PID" ]] || ! kill -0 "$PID" 2>/dev/null; then
  echo "$APP_NAME is not running; pass a live PID as the second argument" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
SAMPLES="$(mktemp -t yuangui-performance.XXXXXX)"
CPU_SORTED="$(mktemp -t yuangui-cpu.XXXXXX)"
VMMAP_SUMMARY="$(mktemp -t yuangui-vmmap.XXXXXX)"
trap 'rm -f "$SAMPLES" "$CPU_SORTED" "$VMMAP_SUMMARY"' EXIT

cpu_centiseconds() {
  awk -v value="$1" 'BEGIN {
    count = split(value, parts, ":")
    seconds = parts[count] + 0
    if (count >= 2) seconds += (parts[count - 1] + 0) * 60
    if (count >= 3) seconds += (parts[count - 2] + 0) * 3600
    printf "%.0f", seconds * 100
  }'
}

PREVIOUS_TIME="$(ps -p "$PID" -o time= | tr -d ' ')"
PREVIOUS_CENTISECONDS="$(cpu_centiseconds "$PREVIOUS_TIME")"
for ((second = 1; second <= DURATION; second++)); do
  sleep 1
  VALUES="$(ps -p "$PID" -o time=,rss= | awk 'NF == 2 { print $1, $2 }')"
  if [[ -z "$VALUES" ]]; then
    echo "$APP_NAME exited during sampling" >&2
    exit 1
  fi
  read -r CURRENT_TIME RSS_KIB <<<"$VALUES"
  CURRENT_CENTISECONDS="$(cpu_centiseconds "$CURRENT_TIME")"
  CPU_PERCENT="$(( CURRENT_CENTISECONDS - PREVIOUS_CENTISECONDS ))"
  PREVIOUS_CENTISECONDS="$CURRENT_CENTISECONDS"
  THREADS="$(ps -M "$PID" | awk 'NR > 1 { count++ } END { print count + 0 }')"
  echo "$second $CPU_PERCENT $RSS_KIB $THREADS" >>"$SAMPLES"
done

/usr/bin/vmmap -summary "$PID" >"$VMMAP_SUMMARY" 2>/dev/null || true

if [[ "$(wc -l <"$SAMPLES" | tr -d ' ')" -lt "$DURATION" ]]; then
  echo "$APP_NAME exited or returned incomplete samples" >&2
  exit 1
fi

awk '{ print $2 }' "$SAMPLES" | sort -n >"$CPU_SORTED"
COUNT="$(wc -l <"$CPU_SORTED" | tr -d ' ')"
MEDIAN_INDEX="$(( (COUNT + 1) / 2 ))"
P95_INDEX="$(( (COUNT * 95 + 99) / 100 ))"
CPU_MEDIAN="$(sed -n "${MEDIAN_INDEX}p" "$CPU_SORTED")"
CPU_P95="$(sed -n "${P95_INDEX}p" "$CPU_SORTED")"
RSS_CURRENT_KB="$(tail -n 1 "$SAMPLES" | awk '{ print $3 }')"
RSS_PEAK_KB="$(awk 'BEGIN { max = 0 } $3 > max { max = $3 } END { print max }' "$SAMPLES")"
THREAD_CURRENT="$(tail -n 1 "$SAMPLES" | awk '{ print $4 }')"
THREAD_PEAK="$(awk 'BEGIN { max = 0 } $4 > max { max = $4 } END { print max }' "$SAMPLES")"
PHYSICAL_CURRENT="$(awk '/^Physical footprint:/ { print $3; exit }' "$VMMAP_SUMMARY")"
PHYSICAL_PEAK="$(awk '/^Physical footprint \(peak\):/ { print $4; exit }' "$VMMAP_SUMMARY")"

{
  echo "YuanGUI idle performance sample"
  echo "timestamp: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "pid: $PID"
  echo "duration_seconds: $DURATION"
  echo "cpu_median_percent: $CPU_MEDIAN"
  echo "cpu_p95_percent: $CPU_P95"
  echo "physical_footprint_current: ${PHYSICAL_CURRENT:-unavailable}"
  echo "physical_footprint_peak: ${PHYSICAL_PEAK:-unavailable}"
  awk -v current="$RSS_CURRENT_KB" -v peak="$RSS_PEAK_KB" 'BEGIN {
    printf "resident_memory_current_mib: %.1f\n", current / 1024
    printf "resident_memory_sample_peak_mib: %.1f\n", peak / 1024
  }'
  echo "threads_current: $THREAD_CURRENT"
  echo "threads_peak: $THREAD_PEAK"
  echo
  echo "vmmap summary"
  /usr/bin/grep -E 'Physical footprint|Physical footprint \(peak\)|TOTAL' "$VMMAP_SUMMARY" || true
  echo
  echo "samples: second cpu_percent resident_memory_kib threads"
  cat "$SAMPLES"
} >"$OUTPUT"

echo "Performance report: $OUTPUT"
echo "CPU median/p95: $CPU_MEDIAN% / $CPU_P95%"
echo "Physical footprint current/peak: ${PHYSICAL_CURRENT:-unavailable} / ${PHYSICAL_PEAK:-unavailable}"
echo "Threads current/peak: $THREAD_CURRENT / $THREAD_PEAK"
