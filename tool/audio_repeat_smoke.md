# Native queue and repeat diagnostic

`audio_repeat_smoke.dart` runs the production queue controller, just_audio,
audio_service handler and native decoder. It records actual source/index changes,
occurrence identities, advancing ayah positions, native final completions, queue
reloads, peak native queue length and peak Dart source registrations. Ordinary
boundaries should use native index changes, not one EOF/reload per recording.

The default mode plays adjacent cached copies of a generated half-second PCM WAV
at volume zero. It runs nine cases: 3/5/10 range repetitions of one/two ayahs,
per-ayah repetitions, a multi-surah playlist, and twelve playback occurrences
before Stop in infinite range mode. Separate introduction occurrences use the
same explicitly synthetic fixture, never evidence about a reciter's content.

Set `AUDIO_SMOKE_AUDIBLE=true` to hear the generated fixture. It contains **40 ms
of head silence and 60 ms of tail silence** per recording. Those 100 ms at a
boundary are intentional recording content. The app does not remove them.

Set `AUDIO_SMOKE_REAL=true` for real EveryAyah downloads/cache playback at audible
volume. This uses the production hash-bound reusable Bismillah sources and
automatically saves the selection without an opening-consent dialog. It runs
seven cases including Al-Ikhlas short ayahs,
Al-Ikhlas/An-Nas introductions, verse/range repetitions and an infinite range.
Run again with networking disabled after all required files have been cached to
check offline transitions. Real cases time out after ten minutes each; generated
cases time out after two minutes. Cache preparation is included in elapsed timing.

The JSON report is `audio_repeat_report.json` in the application-support directory
(Android: `files/audio_repeat_report.json`). It starts as `running` and ends as
`passed` or `failed`; retain the report together with device/OS information.
A queue over six entries or more than seven registered sources including the
root playlist fails the diagnostic. Finite cases require all expected native
occurrences and observable position advancement for each numbered occurrence.

## Timing is not audible gap measurement

Each transition records its native event time, prior duration and
`boundaryEventExcessMs` (event interval minus the previous file duration). This is
a diagnostic of index-event scheduling; callback latency, buffering and duration
updates affect it, and it can be negative. **It does not measure speaker/output
gaps.** `queueLoads` includes initial setup and legitimate exhaustion/recovery.
A normal cached run should normally need one setup.

For an audible check, capture device output or a reliable loopback at known sample
rate while running the audible fixture, then compare waveform boundaries with its
known 40/60 ms source silence. For real recitations, first inspect the decoded
source files' head/tail silence and codec padding, then compare captured output
against that baseline. Record observed output gap separately from index-event
excess. Do not equate quiet material inside a recitation with an application delay.
No crossfade, overlapping recitation or automatic trimming is used.

While a real case plays, lock the screen and check uninterrupted transitions,
notification metadata, Pause/Play/Next/Previous/Stop, Bluetooth/headset controls and
interruption behavior. Capture failures and identify whether the current recording
or a future source failed. Repeat on Android and iOS; one platform cannot certify
the other.

## Android

Use `audio_smoke.init.gradle` for a separate application ID/data directory. It does
not initialize Firebase. From `android` in PowerShell:

```powershell
$audioSmokeTarget = (Resolve-Path ../tool/audio_repeat_smoke.dart).Path
./gradlew.bat :app:assembleDebug "-Ptarget=$audioSmokeTarget" -Ptarget-platform=android-x64 --init-script ../tool/audio_smoke.init.gradle --offline --console=plain
```

Use `android-arm64` for an ARM64 phone. To select real audio, add a base64-encoded
Dart define to that command:

```powershell
$audioSmokeDefines = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('AUDIO_SMOKE_REAL=true'))
# Add "-Pdart-defines=$audioSmokeDefines" to the assembleDebug command above.
```

For audible generated audio, encode `AUDIO_SMOKE_AUDIBLE=true` instead. `--offline`
applies to Gradle dependencies; real audio downloads still need connectivity on
the device for the first run. Check
`build/app/outputs/apk/debug/output-metadata.json` contains the diagnostic ID before
installing. With an explicit device ID:

```text
adb -s DEVICE install -r build/app/outputs/apk/debug/app-debug.apk
adb -s DEVICE shell am start -n com.quran.quran_double_page.audio_smoke/com.quran.quran_double_page.MainActivity
adb -s DEVICE shell run-as com.quran.quran_double_page.audio_smoke cat files/audio_repeat_report.json
```

Remove only the diagnostic package after collecting results. This APK is a
diagnostic, not a release or normal app build.

## iOS

On macOS, use a disposable simulator/test installation:

```text
flutter run -d IOS_SIMULATOR_ID -t tool/audio_repeat_smoke.dart
flutter run -d IOS_SIMULATOR_ID -t tool/audio_repeat_smoke.dart --dart-define=AUDIO_SMOKE_REAL=true
```

This uses AVQueuePlayer. Use a physical iPhone for speaker output and lock-screen
behavior. An Android pass or a Dart test does not substitute for this run.

## Results in this workspace

No Android/iOS device or emulator is available here. The diagnostic has been
analyzed but not run on either native platform. Audible output gaps and locked
screen playback remain unmeasured. See `docs/v5-validation.md` for automated
regression results and content-audit limitations.
