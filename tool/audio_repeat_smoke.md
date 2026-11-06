# Native repeat regression

`audio_repeat_smoke.dart` exercises the production controller, just_audio,
the custom audio_service handler, and the native decoder. It generates a local half-second
PCM WAV and runs nine cases: 3/5/10 repeats of one and two ayahs, per-ayah repeats,
a multi-surah queue, and twelve native completions before Stop in infinite range mode.
It also exercises logical Bismillah items with the generated fixture; it does not
verify the content of any reciter’s Bismillah recording.

Each case requires a native end-of-stream event for each recording (including
separate introductions) and advancing positions for every
expected ayah/repeat. A loop counter or extrapolated playhead alone cannot pass.
Volume is zero: this verifies decoder progression, not audible speaker output.
The harness writes `files/audio_repeat_report.json` inside its app data directory.

## Android

Use `audio_smoke.init.gradle` to give the diagnostic a separate application ID
and data directory, keeping the normal app intact. It does not initialize Firebase.
From the `android` directory in PowerShell:

```powershell
$audioSmokeTarget = (Resolve-Path ../tool/audio_repeat_smoke.dart).Path
./gradlew.bat :app:assembleDebug "-Ptarget=$audioSmokeTarget" -Ptarget-platform=android-x64 --init-script ../tool/audio_smoke.init.gradle --offline --console=plain
```

Use `android-arm64` instead for an ARM64 phone. Check
`build/app/outputs/apk/debug/output-metadata.json` shows the diagnostic application
ID before installing. Then, with an explicit device ID:

```text
adb -s DEVICE install -r build/app/outputs/apk/debug/app-debug.apk
adb -s DEVICE shell am start -n com.quran.quran_double_page.audio_smoke/com.quran.quran_double_page.MainActivity
adb -s DEVICE shell run-as com.quran.quran_double_page.audio_smoke cat files/audio_repeat_report.json
```

The report starts as `running` and ends as `passed` or `failed`. Cases have a
60-second timeout. Remove only the diagnostic package after collecting results.
The APK produced here is a diagnostic, not a release or a normal app build.

## iOS

On macOS, the same entry point can run in a disposable iOS simulator:

```text
flutter run -d IOS_SIMULATOR_ID -t tool/audio_repeat_smoke.dart
```

This path uses the actual AVQueuePlayer implementation. An Android pass does not
substitute for an iOS run. Also check real recitation with audible volume on the
affected device before treating the user's silence report as verified resolved.
