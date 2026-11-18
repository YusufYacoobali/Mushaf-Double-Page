#!/usr/bin/env bash
# CoreSimulator health and bounded recovery for disposable GitHub-hosted macOS VMs.
# Only called inside dedicated simulator jobs, never on a developer's Mac.
set -uo pipefail
MODE="${1:-diagnose}"
OUT="${2:-screenshots/host-health}"
mkdir -p "$OUT"
record() {
  local stage="$1" seconds="$2"; shift 2
  python3 .github/scripts/ci_run.py --operation "$stage" --timeout "$seconds" --output "$OUT" -- "$@" || true
}
echo "Simulator host $MODE: $(sw_vers -productVersion), Xcode=$(xcodebuild -version | head -1)"
echo "Runner image: ${ImageOS:-unknown} / ${ImageVersion:-unknown}" > "$OUT/image.txt"
{ sw_vers; xcodebuild -version; df -h .; sysctl hw.memsize; vm_stat; } >> "$OUT/image.txt" 2>&1 || true
# On macos-15 the FIRST simctl call may spend up to 2.5 minutes mounting
# runtimes (GitHub runner-images #15247). Killing it after 50s then repeating
# only recreates the false "simulator unavailable" failure.
if [[ "$MODE" == "preflight" ]]; then
  record runtimes 200 xcrun simctl runtime list -j
  record devices 105 xcrun simctl list devices -j
else
  record runtimes 75 xcrun simctl runtime list -j
  record devices 75 xcrun simctl list devices -j
fi
if [[ "$MODE" == "diagnose" || "$MODE" == "recover" ]]; then
  record simulator-log 35 log show --last 7m --style compact --predicate 'process == "simdiskimaged" OR process == "cryptexd" OR process == "CoreSimulatorService"'
  { ps -axo pid,stat,command | grep -E 'CoreSimulator|SimLaunchHost|DeviceHub|Simulator\.app' || true; } > "$OUT/processes.txt"
fi
if [[ "$MODE" == "recover" ]]; then
  echo "::warning::CoreSimulator display/launch unresponsive; restarting its service before using another disposable device"
  # A second device cannot help when the host-wide CoreSimulator service is wedged.
  # The GitHub runner is isolated to this one job; no other device tests share it.
  killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
  sleep 7
  record recovered-devices 50 xcrun simctl list devices -j
  record recovered-runtimes 50 xcrun simctl runtime list -j
fi
