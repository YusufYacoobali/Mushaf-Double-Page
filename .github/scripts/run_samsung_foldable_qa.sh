#!/usr/bin/env bash
# Boot one disposable, Samsung-dimension Android AVD and retain real evidence.
set -Eeuo pipefail

PROFILE="${SAMSUNG_QA_PROFILE:?SAMSUNG_QA_PROFILE must name a Samsung profile}"
case "$PROFILE" in
  galaxy-z-fold8|galaxy-z-fold8-ultra) ;;
  *) echo "Unsupported Samsung profile: $PROFILE" >&2; exit 2 ;;
esac
OUT="screenshots-samsung/$PROFILE"
AVD_NAME="quran-${PROFILE}-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
SERIAL="emulator-5554"
IMAGE="system-images;android-36;google_apis;x86_64"
APP_PACKAGE="com.quran.quran_double_page"
EMU_PID=""
mkdir -p "$OUT"

cleanup() {
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    timeout 15 adb -s "$SERIAL" logcat -d -t 1500 > "$OUT/logcat-on-error.txt" 2>&1 || true
    timeout 15 adb -s "$SERIAL" shell dumpsys display > "$OUT/display-on-error.txt" 2>&1 || true
    timeout 15 adb -s "$SERIAL" shell dumpsys window > "$OUT/window-on-error.txt" 2>&1 || true
    timeout 15 adb -s "$SERIAL" shell dumpsys device_state > "$OUT/device-state-on-error.txt" 2>&1 || true
    timeout 15 adb -s "$SERIAL" exec-out screencap -p > "$OUT/screenshot-on-error.png" 2>/dev/null || true
  fi
  timeout 15 adb -s "$SERIAL" emu kill >/dev/null 2>&1 || true
  if [[ -n "$EMU_PID" ]]; then kill "$EMU_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

echo '::group::Create Samsung-dimension stock-Android AVD'
printf 'no\n' | avdmanager create avd --name "$AVD_NAME" --package "$IMAGE"
python3 .github/scripts/prepare_samsung_foldable_avd.py \
  --profile "$PROFILE" --avd-name "$AVD_NAME" \
  --metadata-output "$OUT/profile.json"
cp android-qa-build/build.json "$OUT/build.json"
emulator -version > "$OUT/emulator-version.txt" 2>&1
emulator -accel-check
echo '::endgroup::'

echo '::group::Boot Android and wait for framework readiness'
emulator -avd "$AVD_NAME" -port 5554 -no-window -gpu software \
  -accel on -no-snapshot -wipe-data -writable-system -feature SupportPixelFold -noaudio -no-boot-anim \
  -camera-front none -camera-back none -memory 2048 -cores 2 \
  > "$OUT/emulator.log" 2>&1 &
EMU_PID=$!
export SAMSUNG_QA_SERIAL="$SERIAL" SAMSUNG_QA_EMULATOR_PID="$EMU_PID"
python3 - <<'PY'
import os, subprocess, time
serial = os.environ['SAMSUNG_QA_SERIAL']
pid = int(os.environ['SAMSUNG_QA_EMULATOR_PID'])
deadline = time.monotonic() + 480
ready = 0
while time.monotonic() < deadline:
    try:
        os.kill(pid, 0)
        boot = subprocess.run(['adb', '-s', serial, 'shell', 'getprop', 'sys.boot_completed'],
                              text=True, capture_output=True, timeout=12)
        package = subprocess.run(['adb', '-s', serial, 'shell', 'pm', 'path', 'android'],
                                 text=True, capture_output=True, timeout=12)
        if boot.returncode == 0 and boot.stdout.strip() == '1' and package.stdout.startswith('package:'):
            ready += 1
            if ready >= 3:
                print('Android boot and package manager ready', flush=True)
                break
        else:
            ready = 0
    except ProcessLookupError:
        raise SystemExit('Android emulator exited during startup; inspect emulator.log')
    except subprocess.TimeoutExpired:
        ready = 0
    print('Waiting for Android framework readiness...', flush=True)
    time.sleep(3)
else:
    raise SystemExit('Android emulator framework startup timed out after480seconds')
PY
python3 .github/scripts/prepare_samsung_foldable_avd.py \
  --initialize-guest --serial "$SERIAL" --profile-metadata "$OUT/profile.json"
timeout 20 adb -s "$SERIAL" shell input keyevent KEYCODE_WAKEUP
timeout 20 adb -s "$SERIAL" shell wm dismiss-keyguard
timeout 20 adb -s "$SERIAL" shell settings put global window_animation_scale 0
timeout 20 adb -s "$SERIAL" shell settings put global transition_animation_scale 0
timeout 20 adb -s "$SERIAL" shell settings put global animator_duration_scale 0
timeout 20 adb -s "$SERIAL" shell settings put system screen_off_timeout 1800000
timeout 20 adb -s "$SERIAL" shell svc power stayon true
timeout 20 adb -s "$SERIAL" shell cmd device_state print-states > "$OUT/supported-device-states.txt"
echo '::endgroup::'

echo '::group::Install the exact shared APK'
timeout 180 adb -s "$SERIAL" install -r -g android-qa-build/reader.apk
timeout 20 adb -s "$SERIAL" shell pm grant "$APP_PACKAGE" android.permission.POST_NOTIFICATIONS
echo '::endgroup::'

echo '::group::Capture real pages at each native fold posture'
python3 .github/scripts/capture_android_foldable.py \
  --serial "$SERIAL" --profile "$PROFILE" --profile-metadata "$OUT/profile.json" \
  --output "$OUT" --page "${READER_QA_PAGE:-6}"
echo '::endgroup::'
