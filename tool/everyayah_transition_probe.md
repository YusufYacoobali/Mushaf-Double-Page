# Native split-signal output probe

This diagnostic does not alter any EveryAyah recording or production UI. It
requires Python + NumPy + FFmpeg for fixture generation/analysis and a native
Flutter installation for playback/output capture.

## Prepare synthetic files

Use an empty directory outside the repository:

```sh
python3 tool/everyayah_transition_probe.py generate --directory /tmp/transition_probe
```

The default is 44.1 kHz; use `--sample-rate 48000` for a 48 kHz capture route.
Two MP3s are independently encoded from one uninterrupted signal. The manifest
binds their bytes and the decoded/reference/control WAVs; each part has exactly
1.5 seconds of decoded samples after normal codec-padding handling. Nothing is
amplitude-trimmed, joined as MP3 bytes or used as real recitation evidence.

Copy the directory into the diagnostic app's application-support directory as
`transition_probe/`, or supply an app-readable absolute directory using
`--dart-define=AUDIO_TRANSITION_DIRECTORY=/absolute/path`. For Android use the
separate smoke-test application ID from `audio_smoke.init.gradle`, then `adb
run-as`/Android Studio Device Explorer to copy into that package's `files` directory.
For an iOS test container use Xcode Devices/Simulator container tools to copy into
`Library/Application Support`. Keep the manifest and all generated files together;
no network is used for playback. Do not overwrite a normal app's recitation cache.

## Capture baseline, candidate and unsplit control

Build the target `tool/everyayah_transition_probe.dart` on the desired platform
using the diagnostic application ID. For example, on a selected simulator:

```sh
flutter run -d DEVICE_ID -t tool/everyayah_transition_probe.dart
flutter run -d DEVICE_ID -t tool/everyayah_transition_probe.dart --dart-define=AUDIO_TRANSITION_LEGACY=true
flutter run -d DEVICE_ID -t tool/everyayah_transition_probe.dart --dart-define=AUDIO_TRANSITION_CONTROL=true
```

Use the Android smoke init script with `-Ptarget` set to this target when building
that separate APK. Capture output through a trustworthy native loopback/wired
interface as signed 16-bit PCM WAV at the fixture's sample rate. Start capture
before playback; arbitrary leading capture latency is harmless. The split target
plans three repetitions so the normal bounded queue receives future edits, then
stops when cycle two begins: only the first two signal landmarks play completely.
The control plays the entire unsplit signal once. The target shares the native
player/background handler and records occurrence events, not an output-gap value.

The default split probe now exercises the progressive continuous PCM backend on
iOS/Android. `AUDIO_TRANSITION_LEGACY=true` selects the old split-MP3 backend for
a same-build baseline; it is a diagnostic-only selector, not a production feature
flag. The unsplit WAV control uses just_audio. Event reports name the actual
backend and fallback reason: reject a candidate capture that fell back to legacy.
`firstRenderedEventUs` is throttled telemetry, not an acoustic onset measurement.

For baseline use cleanup commit `eb638da` (copy only the diagnostic tools into an
isolated checkout); for candidate use the second delivery commit. Compare the
same device, route, volume and sample rate. A simulator is useful for native
setup but does not certify physical speaker/headphone behavior.

```sh
python3 tool/everyayah_transition_probe.py measure --directory /tmp/transition_probe \
  --capture /tmp/baseline.wav --platform ios --stage baseline --output /tmp/baseline.json
python3 tool/everyayah_transition_probe.py measure --directory /tmp/transition_probe \
  --capture /tmp/candidate.wav --platform ios --stage candidate --output /tmp/candidate.json
python3 tool/everyayah_transition_probe.py measure --directory /tmp/transition_probe \
  --capture /tmp/control.wav --platform ios --stage control --output /tmp/control.json
```

Choose `--platform android` for Android captures. Preserve original captures and
reference files. The tool refuses to overwrite them, rejects mismatched rates
and poor signal correlation, and reports landmark-spacing excess in frames/ms.
It retains channels instead of mixing possible antiphase channels to silence.
Subtracting/comparing the unsplit control helps distinguish route clock drift,
resampling and capture effects from item-switching delay. These effects determine
physical measurement uncertainty; the analyzer's exact synthetic result is not
an uncertainty estimate for a phone.

## Local analyzer/native-order regressions

```sh
python3 -m unittest discover -s tool -p test_everyayah_transition_probe.py -v
cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
  tool/native_tests/queue_prefix_test.c -o /tmp/queue_prefix_test
ASAN_OPTIONS=detect_leaks=0 /tmp/queue_prefix_test
```

The analyzer self-test recovers a known 100 ms insertion and zero insertion
exactly, despite startup delay/gain changes. It rejects silent/unusable captures.
The C test validates the actual native queue-prefix helper and suffix order. These
are **not measurements of AVQueuePlayer, ExoPlayer or speaker output**.

Follow up with the real Alafasy/Husary/Shaatree cached/offline suite described in
`audio_repeat_smoke.md`, including background controls, interruptions, repeats,
Surah Queue, Bismillah and source/route changes. Native before/after capture has
not been performed in this Linux-only workspace.
