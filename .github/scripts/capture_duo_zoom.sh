#!/usr/bin/env bash
# Capture the *actual rendered reader* at both zoom extremes, using the
# app's real visible +/- controls, not a mocked widget or synthetic layout.
set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "Usage: $0 <state-label> <min-percent> <max-percent>" >&2
  exit 2
fi
LABEL="$1"
MIN="$2"
MAX="$3"
UDID="${DUOCTL_UDID:?DUOCTL_UDID must be set}"
mkdir -p screenshots

ui_file="screenshots/${LABEL}-accessibility.txt"

read_ui() {
  axe describe-ui --udid "$UDID" > "$ui_file"
}

# An expanded dock automatically collapses after ten seconds of inactivity.
# Reopen it whenever needed rather than tapping invisible controls.
ensure_dock() {
  read_ui
  if grep -Fq 'Zoom out' "$ui_file" && grep -Fq 'Zoom in' "$ui_file"; then
    return 0
  fi
  if grep -Fq 'Open navigation' "$ui_file"; then
    axe tap --label "Open navigation" --udid "$UDID"
    sleep 0.5
    read_ui
  fi
  if ! grep -Fq 'Zoom out' "$ui_file" || ! grep -Fq 'Zoom in' "$ui_file"; then
    echo "::error::${LABEL}: cannot find both reader zoom buttons in the simulator accessibility tree"
    return 1
  fi
}

# The zoom range is 5%-incremented. Read the on-screen percentage after every
# tap, and refuse to label an image "minimum"/"maximum" without proof.
reach_percent() {
  local target="$1"
  local button="$2"
  local reached=0
  local percent
  for attempt in $(seq 1 13); do
    ensure_dock
    if grep -Fq "${target}%" "$ui_file"; then
      reached=1
      break
    fi
    axe tap --label "$button" --udid "$UDID"
    sleep 0.15
  done
  ensure_dock
  if grep -Fq "${target}%" "$ui_file"; then
    reached=1
  fi
  if [[ "$reached" -ne 1 ]]; then
    echo "::error::${LABEL}: expected ${target}% after using '$button' but the displayed zoom never reached it"
    return 1
  fi
  percent=$(grep -Eo '(60|65|70|75|80|85|90|95|100)%' "$ui_file" | sort -u | tr '\n' ' ' || true)
  echo "${LABEL}: verified ${target}% (visible zoom values: ${percent})"
}

# Record the actual device state, UI tree and PNG together for human review.
snapshot() {
  local suffix="$1"
  duoctl state > "screenshots/${LABEL}-${suffix}-state.json"
  read_ui
  cp "$ui_file" "screenshots/${LABEL}-${suffix}-accessibility.txt"
  duoctl screenshot "screenshots/${LABEL}-${suffix}.png"
}

ensure_dock
reach_percent "$MIN" 'Zoom out'
snapshot "min-${MIN}pct"
reach_percent "$MAX" 'Zoom in'
snapshot "max-${MAX}pct"
echo "Captured actual rendered ${LABEL} reader at ${MIN}% and ${MAX}%."
