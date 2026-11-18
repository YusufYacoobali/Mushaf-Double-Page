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
if [[ "$MODE" == "recover" ]]; then
  echo "::warning::CoreSimulator display/launch unresponsive; restarting its host service"
  # This runner is isolated to one job. A second device on a wedged host
  # cannot recover until the CoreSimulator service itself is restarted.
  killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1 || true
  sleep 7
  # The FIRST simctl call on macos-15 can need 2.5 minutes for runtime mounts.
  record recovered-runtimes 185 xcrun simctl runtime list -j
  record recovered-devices 95 xcrun simctl list devices -j
  record simulator-log 25 log show --last 7m --style compact --predicate 'process == "simdiskimaged" OR process == "cryptexd" OR process == "CoreSimulatorService"'
  exit 0
fi
# On macos-15 the FIRST simctl call may spend up to 2.5 minutes mounting
# runtimes (GitHub runner-images #15247). Don't kill it early and retry.
if [[ "$MODE" == "preflight" ]]; then
  record runtimes 200 xcrun simctl runtime list -j
  record devices 105 xcrun simctl list devices -j
else
  record runtimes 75 xcrun simctl runtime list -j
  record devices 75 xcrun simctl list devices -j
  record simulator-log 35 log show --last 7m --style compact --predicate 'process == "simdiskimaged" OR process == "cryptexd" OR process == "CoreSimulatorService"'
  { ps -axo pid,stat,command | grep -E 'CoreSimulator|SimLaunchHost|DeviceHub|Simulator\\.app' || true; } > "$OUT/processes.txt"
fi
