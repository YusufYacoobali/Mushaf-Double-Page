# Progressive continuous EveryAyah playback

## Activation and delivery scope

Continuous PCM is the **default on iOS and Android**, including release builds.
There is no production feature flag. This follows the explicit delivery request.
Other platforms use the existing EveryAyah `just_audio` backend. Native setup,
decode, output, route-invalidating and stall failures hand off to that backend.
EveryAyah remains the only recording provider; the audio UI is unchanged.

The implementation covers the native engines, progressive producer, existing
cursor modes and fallback. **Physical iPhone/Android output, energy, thermal and
long-session performance acceptance is still required.** Default activation is
not a claim that those measurements have been performed. The Linux environment
cannot build or run the Apple implementation.

| Milestone | Implementation | Validation |
| --- | --- | --- |
| A: native engine | Local `quran_pcm_audio` plugin, Android MediaCodec/AudioTrack and iOS AVAudioFile/AVAudioConverter/AVAudioEngine | Android compile/native tests; Apple XCTest sources provided, require macOS |
| B: progressive producer | Existing repository scheduler, first-recording startup, bounded native FIFO/scheduling and short-recording reuse | Delayed-next-download regression; native runtime tests below |
| C: playback modes | Existing controller/cursor, ranges, full surahs, queues, introductions, finite/infinite repeats, navigation, background handler and Journey | Existing regression suite plus continuous backend contract tests |
| D: reliability | Generation cancellation, paused intent, played-frame clock, bounded resources, dispose-before-fallback | Long repeat, boundary, startup, seek and fallback regressions |
| E: activation | Default for both mobile platforms, legacy fallback retained | Physical-device acceptance remains outstanding |

## Ownership and data flow

`QuranAudioController` remains the only selection, repetition and intent state
machine. `QuranAudioHandler` remains the sole audio_service/media-control bridge.
`AudioPlaybackBackend` exposes prepare, queue, finish, play, pause, stop, seek,
position/state/error streams and disposal. `JustAudioBackend` wraps the existing
vendored player. `ContinuousPcmBackend` transfers paths, occurrence IDs and
commands through a MethodChannel; PCM never crosses Flutter's UI isolate.

The existing repository obtains the first original MP3, then the controller starts
the backend and immediately prepares its next three logical occurrences. It does
not await the selected range, full surah, queue or automatic offline-save task.
The repository's shared two-request scheduler still reserves capacity for urgent
playback. Its cache, audit hashes, physical-recording deduplication, background
saving, retry and cancellation rules remain in force.

Native workers decode and append incrementally. All native playback items are
PCM chunks within one output, rather than separate MP3 playback items. Ordinary
ayah/repeat/surah transitions do not call pause, play, seek, stop or prepare.
`finishQueue` distinguishes a finite selection's real EOF from a temporary shortage
of downloaded recordings. A shortage reports Buffering and retains the output.

## Formats and integrity

Both engines use a stable 44,100 Hz stereo output. Android uses signed 16-bit PCM;
iOS uses non-interleaved float PCM. Compatible recordings avoid resampling. Mono
and different rates are converted without recreating output.

Android uses MediaExtractor and MediaCodec. Only extractor-declared encoder
delay/padding may be removed. Those values are zeroed in the codec configuration
so the explicit bounded trimmer is the sole owner. Streaming linear resampling retains
its phase and last source frame across codec chunks, and has an exact rational
output count. Device regressions compare native counts with independent FFmpeg
references from the existing unmodified EveryAyah fixtures. Decoder implementations
must still be compared on representative physical devices, especially their
gapless metadata handling and non-44.1 kHz output fidelity.

iOS uses Core Audio's incremental `AVAudioFile` MP3 decoder, including its native
packet-table priming/remainder handling. `AVAudioConverter` handles differing
formats; compatible stereo PCM is scheduled directly. Apple native decoder/count
and converter verification remains a macOS/device acceptance requirement.

Neither path concatenates compressed bytes, examines amplitude to trim quiet
audio, inserts boundary silence, fades, overlaps, changes playback speed or writes
WAVs. The Stage-A WAV tool and proof target remain development-only reference
tools. They do not implement production startup or offline caching.

## Resource limits

The controller and native metadata queues retain at most six occurrences. The
default rolling budget is eight seconds, configurable in the backend constructor
from one to fifteen seconds. Long recordings are read incrementally; codec output
is handed off in chunks of at most 4,096 output frames.

Android has a bounded producer FIFO and a separate nonblocking AudioTrack writer.
AudioTrack's hardware-facing buffer is the greater of 100 ms or twice the native
minimum, rather than an eight-second startup threshold. iOS budgets all buffers
retained by AVAudioPlayerNode against the same rolling window. The decode worker
waits on a condition variable for capacity; neither platform blocks its real-time
rendering thread on download, conversion, channel traffic or Flutter work.

Each native generation also has an LRU cache of at most two seconds and eight
short recordings. Repetition reuses the same PCM arrays/buffers where eligible.
Longer recordings use the canonical MP3 cache and incremental re-decoding. Cache
and rolling limits are separate: the default retained PCM budget is approximately
ten seconds, plus one worker chunk and Android's hardware-facing buffer. This is
roughly 1.8 MB of Android PCM or 3.6 MB of iOS PCM; these are **calculated bounds,
not measured process RSS** and exclude codec/engine/framework overhead.

Stop, selection replacement, fallback and Flutter-engine teardown cancel producers,
wake blocked workers and release native output. Position timers stop when output
is absent. No temporary PCM files or persistent uncompressed cache are created.

## Timeline, clock and controls

Each native row contains an occurrence ID, exact starting output frame, actual
decoded frames and, after EOF, exclusive ending frame. The ID maps back to the
controller's reciter, recording identity, surah, ayah/introduction, verse repeat
and range cycle. A long recording's duration can remain unknown until its EOF is
decoded; no duration estimate is substituted. Consumed rows and source definitions
are pruned, including during infinite repetition.

The clock measures presentation rather than queue writes. Android prefers a
fresh AudioTimestamp, capped by played frames, with playback-head/wrap handling
and a frozen paused clock. Stale timestamps cannot extrapolate across an underrun.
iOS maps the player-node rendering clock through scheduled chunks, accounts for
downstream output latency and reconciles data-played-back callbacks. Actual
speaker/Bluetooth latency and route-dependent accuracy still need measurement.

Position telemetry is throttled to 10 Hz. Half-open frame intervals select the
logical cursor; the UI inherits this update cadence, not per-sample notification
precision. Existing metadata, highlighting, page following and Journey consume
that same cursor. Repeated recordings retain distinct occurrence identities.

Manual navigation and in-ayah seeking may flush/reposition output. They re-decode
from cached compressed input, discard only frames before the requested seek point,
and preserve Play/Pause intent. They never require a full-selection decode or WAV.
Finite EOF is retained across a seek. Seeking within already-scheduled PCM is a
possible later optimization; current navigation favors a deterministic restart
from the requested recording and frame.

AudioSession activation uses the existing speech configuration. No native plugin
creates an independent focus owner or foreground service. Existing notification,
lock-screen, Bluetooth, noisy-route and interruption commands still reach the same
controller. Interruption end does not grant permission to resume. Route changes
that invalidate Apple's scheduled output fail explicitly into legacy playback
instead of silently losing scheduled recitation.

## Recovery

A continuous failure first disposes its native output, then installs the legacy
backend at the **rendered current occurrence**, even when a future decode failed.
The plan, occurrence ID, repeat counters and paused intent survive. The current
ayah restarts from its beginning because decoder-relative offsets cannot be
guaranteed equivalent. Failure to release output prevents a competing engine from
starting. Cancellation generations reject late native events and focus requests.

`activeBackend`, `continuousFallbackReason` and native `diagnostics` expose backend,
rendered frames, buffered/capacity frames and underruns for development. Fallback
reasons are logged with `debugPrint`; no diagnostic labels are added to the UI.

## Reproduce validation

```sh
flutter analyze
flutter test
git diff --check
python3 -m unittest discover -s tool -p 'test_*.py'
flutter build apk --debug
cd android
./gradlew :quran_pcm_audio:testDebugUnitTest
./gradlew :quran_pcm_audio:connectedDebugAndroidTest
```

The JVM suite checks exact equal-rate sample ordering, mono/quiet preservation,
chunk-independent resampling/counts, metadata trimming and cache bounds/reuse.
Android instrumentation uses the original repository fixtures, independently
computed FFmpeg frame counts and a real AudioTrack. It checks bounded PCM,
continuous occurrence frame ranges, played-frame progression, finite EOF and Pause.
It is not a speaker output capture or battery measurement.

On a macOS machine with Flutter/Xcode/CocoaPods:

```sh
flutter build ios --simulator --debug
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:RunnerTests test CODE_SIGNING_ALLOWED=NO
```

Choose an installed simulator. RunnerTests includes incremental exact stereo/quiet
sample comparison, missing-input failure and an AVAudioEngine occurrence timeline
test. Then build/run on a physical iPhone; simulator output cannot certify routes.

For added-gap measurements, use `tool/everyayah_transition_probe.md`. The probe
now defaults to continuous PCM. `AUDIO_TRANSITION_LEGACY=true` selects the diagnostic
legacy baseline; `AUDIO_TRANSITION_CONTROL=true` plays the unsplit control through
just_audio. These selectors apply only to that synthetic test target. Its recorded
first-rendered event is a 10 Hz telemetry measurement, not an acoustic onset time.
Capture and analyze actual output using the existing Python landmark analyzer.

Before calling device acceptance complete, measure cold/cached first audible
startup, additional boundary gap against the decoded reference, CPU/RSS, decode
throughput, battery/thermal load and underruns on iPhone and Android. Include the
Yasser 55:1–10 proof originals, all 22 reciters' available recordings, different
source formats, Bismillah, repetitions, long Al-Baqarah/Surah Queues, seek, reciter
replacement, offline/error recovery, speaker/wired/Bluetooth routes, background
controls, calls, disconnection and both Mushaf editions. Preserve natural recorded
quiet; the acceptance metric is **additional output gap**, not total silence.

## Validation results for this delivery

Checks on 7 November 2026:

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub` | No issues |
| Full `flutter test --no-pub` | **419 passed**, two existing artifact/product-mode checks skipped in the default run |
| Separate product-mode proof guard check | Passed; the old WAV proof remains development-only |
| Python audio tools | **8 passed** |
| Existing native C queue tests, ASan/UBSan | Passed |
| Android debug APK | Built, including generated registration of the new native plugin |
| Native Android JVM tests | **6 passed**; 0.198 s test runtime |
| Android 10/API 29 emulator instrumentation | **2 passed**; 69.936 s total reported runtime on software emulation |
| `git diff --check` | Clean |
| iOS build and XCTest | Unavailable: Linux host has no Xcode/macOS SDK |

Native Android decoding matched independent FFmpeg frame counts exactly for
Alafasy 112:1 (**128,639** frames), Husary 112:4 (**358,272**), Shaatree 113:5
(**201,600**) and Minshawy Mujawwad 112:3 (**546,048**). The real AudioTrack
test played three consecutive Alafasy occurrences through one output, ended at
**385,917** frames, retained exact adjacent occurrence bounds, stayed below
**66,150** queued frames with a one-second producer budget, and froze its clock
during a 250 ms Pause. Test runtime includes decoding, setup and software-emulator
overhead; it is not a production startup or decode-throughput measurement.

The first emulator runs could not query the device API level during slow software
boot. After boot, a session-only `ddmlib.getprop.timeout.sec=60` accommodated slow
property reads and both native tests completed. No such emulator setting is added
to the application. No physical phone, output capture, acoustic onset/gap, CPU,
battery or thermal measurements were available. Apple compilation and native
MP3/converter validation remain outstanding. Default activation follows the user
request; these device-validation limits remain explicit.
