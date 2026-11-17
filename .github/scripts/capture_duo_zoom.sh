#!/usr/bin/env bash
# Drive the real reader's on-screen zoom buttons, verify actual percentages and
# capture the rendered app. Never synthesize page images or assume tap success.
set -euo pipefail
if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 <state-label> <min-percent> <max-percent>" >&2
  exit 2
fi
LABEL="$1"; MIN="$2"; MAX="$3"
: "${DUOCTL_UDID:?DUOCTL_UDID must be set}"
mkdir -p screenshots
UI="screenshots/${LABEL}-accessibility.json"

read_ui() {
  local attempt
  for attempt in 1 2 3; do
    if duoctl elements > "$UI" && python3 -m json.tool "$UI" > /dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "::error::${LABEL}: Duo accessibility tree unavailable"
  return 1
}
tap_button() {
  local coords x y
  coords="$(python3 .github/scripts/duo_accessibility_tap.py "$UI" "$1")" || return 1
  read -r x y <<< "$coords"
  echo "${LABEL}: tap '$1' at ${x},${y}"
  duoctl tap "$x" "$y"
}
ensure_dock() {
  read_ui || return 1
  if grep -Fq 'Zoom out' "$UI" && grep -Fq 'Zoom in' "$UI"; then return 0; fi
  if grep -Fq 'Open navigation' "$UI"; then
    tap_button "Open navigation" || return 1
    sleep .6
    read_ui || return 1
  fi
  if ! grep -Fq 'Zoom out' "$UI" || ! grep -Fq 'Zoom in' "$UI"; then
    echo "::error::${LABEL}: dock did not expose both zoom buttons"
    return 1
  fi
}
current_zoom() {
  local found
  found=$(grep -Eo '(^|[^0-9])(60|65|70|75|80|85|90|95|100)%' "$UI" | grep -Eo '(60|65|70|75|80|85|90|95|100)%' | sort -u || true)
  local count
  count=$(printf '%s\n' "$found" | grep -c '[0-9]' || true)
  if [[ "$count" != 1 ]]; then
    echo "::error::${LABEL}: cannot read a unique displayed zoom percent; found: ${found:-none}" >&2
    return 1
  fi
  printf '%s\n' "${found%%%}"
}
reach_zoom() {
  local target="$1"
  local current action n
  for n in $(seq 1 17); do
    ensure_dock || return 1
    current="$(current_zoom)" || return 1
    if [[ "$current" -eq "$target" ]]; then
      echo "${LABEL}: VERIFIED real displayed zoom ${target}%"
      return 0
    fi
    if [[ "$current" -gt "$target" ]]; then action="Zoom out"; else action="Zoom in"; fi
    tap_button "$action" || return 1
    sleep .25
  done
  ensure_dock || true
  echo "::error::${LABEL}: unable to reach ${target}% using real buttons"
  return 1
}
snapshot() {
  local state="$1" 
  duoctl state > "screenshots/${LABEL}-${state}-state.json"
  read_ui
  cp "$UI" "screenshots/${LABEL}-${state}-accessibility.json"
  duoctl screenshot "screenshots/${LABEL}-${state}.png"
}
fail_with_evidence() {
  echo "FAILED: ${LABEL} $1" | tee -a "screenshots/${LABEL}-result.txt"
  duoctl screenshot "screenshots/${LABEL}-failed.png" || true
  cp "$UI" "screenshots/${LABEL}-failed-accessibility.json" 2>/dev/null || true
  exit 1
}
echo "Testing ${LABEL}: ${MIN}% to ${MAX}%" | tee "screenshots/${LABEL}-result.txt"
ensure_dock || fail_with_evidence "dock not accessible"
reach_zoom "$MIN" || fail_with_evidence "minimum zoom ${MIN}%"
snapshot "min-${MIN}pct" || fail_with_evidence "minimum screenshot"
reach_zoom "$MAX" || fail_with_evidence "maximum zoom ${MAX}%"
snapshot "max-${MAX}pct" || fail_with_evidence "maximum screenshot"
echo "PASS: ${LABEL} ${MIN}% / ${MAX}%" | tee -a "screenshots/${LABEL}-result.txt"
