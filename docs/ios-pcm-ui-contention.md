# iOS playback during Tasbeeh interaction

The reported symptom was repeated glitches that recovered while a queue of three
short surahs played during Tasbeeh interaction. The supplied console output shows
UIKit keyboard/layout warnings and a gesture timeout, without a PCM error or
buffer measurement. It does not establish the cause of the audible glitch.

The previous output did synchronously dispatch every decoded buffer to the main
queue. Playback completions and presentation-clock updates also depended on main.
UI contention could therefore delay scheduling or keep the bounded producer asleep
after rendered buffers had freed capacity.

## Thread ownership

- `quran.pcm.commands` serializes Flutter lifecycle commands off main.
- `quran.pcm.output` owns AVAudioEngine/AVAudioPlayerNode access, buffer scheduling,
  completion handling, route validation and a 50 ms presentation-clock timer.
- `quran.pcm.decode` decodes incrementally. It waits on bounded capacity, releases
  the condition lock, then schedules through the output queue. No condition lock
  is held while waiting for that queue.
- Main handles Flutter replies and 100 ms telemetry. Telemetry only copies state
  protected by the condition; it does not poll AVFoundation or release capacity.

There is no synchronous main dispatch in the native output path. Delayed Flutter
telemetry cannot stop the native clock or completion handling. New recording paths
still arrive from Dart, so an indefinitely blocked Dart isolate can exhaust the
bounded queue. This change does not guarantee playback through arbitrary freezes.

Tasbeeh changes update the counter immediately. JSON encoding and serialized
platform writes checkpoint the latest snapshot every 250 ms while counting rather
than on every tap. Successful saves no longer cause an extra UI notification.
Existing route-exit/background flushes persist the latest state immediately;
dispose drains a pending checkpoint. Failed saves retain the newest count for
retry without continuously retrying in the background.

## Diagnostics and recovery

Native `[QuranPCM] underrun`/`resumed` messages log transitions independently of
Flutter. Snapshots include rendered and buffered frames, capacity, scheduled and
completed buffer counts, maximum scheduling wait, queued recordings, the decoding
occurrence, and the minimum observed buffer level. Flutter logs the same snapshot
when its observed underrun count increases, plus the cursor on backend handoff.

Transient shortages retain the output, frame clock and occurrence order. They do
not restart an ayah or skip to the next recording. Error snapshots adopt the
latest rendered cursor before fallback, including boundaries the UI missed while
busy. The existing unrecoverable-failure policy still restarts that current ayah
from its beginning after disposing the native engine; this is not sample-exact
continuation between different decoders.

## Verification and device follow-up

The Flutter regression combines surahs 112, 113 and 114 (synthetic recording paths
and explicitly advanced native frames) with rapid taps on the actual Tasbeeh UI.
It checks occurrence order, count preservation, finite completion, one native
prepare/play, and no legacy starts during transient buffering. Separate tests
cover save coalescing, failed-save retry, disposal and delayed error handoff.

Checks on 7 November 2026: `flutter analyze --no-pub` reported no issues;
the full Flutter suite passed **453 tests**, with two existing optional checks
skipped. The portable Swift executable below passed with warnings treated as
errors, all plugin/XCTest Swift sources passed syntax parsing, and
`git diff --check` was clean.

`tool/native_tests/pcm_output_concurrency_test.swift` runs the production serial
queue and frame clock with main deliberately blocked. It checks serial ordering,
timer progress, paused clock behavior and sample accounting across an underrun.
It can run on Linux with Swift 5 language mode:

```sh
swiftc -swift-version 5 -warnings-as-errors \
  packages/quran_pcm_audio/ios/Classes/PcmAudioQueue.swift \
  packages/quran_pcm_audio/ios/Classes/PcmFrameClock.swift \
  tool/native_tests/pcm_output_concurrency_test.swift -o /tmp/pcm_concurrency_test
/tmp/pcm_concurrency_test
```

An Apple XCTest additionally schedules three recordings through real AVFoundation,
blocks main while a one-second rolling window drains/refills, pauses/resumes and
checks the final frame count and occurrence boundaries. This test and iOS output
capture require macOS/Xcode and have not been run in the Linux workspace. Parsing
Swift source and passing portable tests do not establish iOS build/device success.

On the Mac, run `flutter pub get` and `cd ios && pod install` before rebuilding so
the local pod includes the extracted Swift source files. Run RunnerTests, then
queue three short surahs on the affected iPhone and count rapidly in Tasbeeh,
including opening/closing custom-dhikr input. Capture the `[QuranPCM]` messages
and listen across every ayah/surah boundary. Repeat with cached recordings to
separate output scheduling from network starvation. Physical-device confirmation
of smooth playback remains outstanding; unrelated keyboard warnings are unchanged.
