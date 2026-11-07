# EveryAyah native transition latency

Investigation on 7 November 2026, following the separate EveryAyah-only cleanup
commit `eb638da`. The reported approximately 100 ms gap at **cached MP3 file
transitions** is the primary symptom. Source quiet is not treated as its cause,
and no recitation is trimmed, faded, overlapped, transcoded or rewritten.

## What was identified and changed

**iOS:** the vendored `just_audio` Darwin `enqueueFrom:` preserved the current
`AVPlayerItem` but removed and reinserted every other queued item on ordinary
playlist edits. Dart's bounded window appends future occurrences and removes
consumed prefixes throughout playback. Even an append outside the native lazy
treadmill rebuilt the same next item. This unnecessary queue churn forfeits the
next item's uninterrupted queue residency/preparation. It is a real wrapper
problem and a plausible contributor to latency; its contribution in milliseconds
has not been measured on a device.

The small Approach A fix retains the common **identity-matching native prefix**
when the current item is unchanged and native loop mode is off. Only a divergent
suffix is removed/appended. If the desired treadmill is `[current, next]` both
before and after an edit, native remove/insert calls drop from **two to zero**.
Reordering/removing the actual next item still repairs the suffix. Current-item
changes, seeks and native loop-one/all retain the existing implementation and
secondary-item handling. The app's repeat modes remain logical occurrences using
native loop-off, so their unchanged upcoming items benefit as well.

The native treadmill remains two lazy items, the Dart window three upcoming
occurrences, the native playlist at most six and retained Dart sources bounded.
There is no window-size increase, new decoder, output rescheduling, playback
offset or periodic pause/reload. Original MP3s and encoder metadata remain intact.

**Android:** no equivalent wrapper-level per-ayah stop/reload was identified.
The wrapper uses Media3 **1.4.1**, progressive local-file sources, an existing
ExoPlayer, default gapless extractors and disabled offload. Appends/removals use
playlist mutation APIs, not `setMediaSources`/`prepare` at each ordinary boundary.
The renderer/sink review was performed against these upstream 1.4.1 sources:

- [Mp3Extractor](https://github.com/androidx/media/blob/1.4.1/libraries/extractor/src/main/java/androidx/media3/extractor/mp3/Mp3Extractor.java)
  puts encoder delay/padding into `Format` from available ID3/Xing/LAME metadata.
- [MediaCodecInfo](https://github.com/androidx/media/blob/1.4.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/mediacodec/MediaCodecInfo.java)
  permits compatible audio decoder reuse **with a flush**; different formats or
  workarounds can require reinitialisation. It is not accurate to claim the
  decoder never flushes or changes between MP3s.
- [MediaCodecAudioRenderer](https://github.com/androidx/media/blob/1.4.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/audio/MediaCodecAudioRenderer.java)
  evaluates codec reuse and reports stream discontinuities to the existing sink.
- [DefaultAudioSink](https://github.com/androidx/media/blob/1.4.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/audio/DefaultAudioSink.java)
  reuses compatible AudioTracks, draining prior data; incompatible configurations
  may recreate the track. `TrimmingAudioProcessor` receives the format's explicit
  encoder-delay/padding values. No additional silence-based trimming is added.

No device-specific decoder recreation, AudioTrack underrun or 100 ms sink stall
was captured here. Android engine settings and Media3 version are unchanged;
there is no unmeasured Android latency fix claimed.

**App/repository:** cached lookahead is prepared independently of occupied
network workers. Only the first recording must be ready before automatic Play;
lookahead and offline saving continue asynchronously. Healthy prepared boundaries
adopt native occurrence changes without pause, seek, stop, reload or recovery.
The four-reciter actual-MP3 regressions and 2,500-transition/source-retention tests
continue checking this. Cache scheduling remains two requests, at most one
background request. No new application playback state machine was introduced.

## Reproducible baseline and measurements

The new [split-signal probe](../tool/everyayah_transition_probe.md) generates two
MP3s from one uninterrupted, uniquely coded signal. Each MP3 decodes to exactly
66,150 frames at 44.1 kHz, including the decoder's handling of reliable codec
padding metadata. It introduces no intentional inter-file silence. A native
Flutter target exercises the production controller/player/background bridge with
ordinary bounded lookahead edits. A separate unsplit control uses the same route.

The Python measurement tool locates interior signal landmarks in an actual
captured PCM WAV, then compares their spacing with the decoded source reference.
It does not derive audible gaps from Dart index events or amplitude thresholds.
Both capture and reference must use the same sample rate; unreliable correlation
and changed reference files are rejected. Clock drift/resampling/route effects
must be assessed with the unsplit control and reported as uncertainty.

| Check | Baseline | Candidate | Evidence limit |
| --- | --- | --- | --- |
| Stable iOS next-item queue edit | remove + reinsert same prepared item | retains item; zero remove/insert | Native prefix/order algorithm tests and implementation review, not Apple output capture. |
| Synthetic analyzer, uninterrupted reference | 0 extra frames | 0 extra frames | Analyzer self-test, not native playback. |
| Synthetic analyzer, known injected gap | 4,410 frames / 100 ms | detects 4,410 frames / 100 ms | Proves measurement sensitivity; does not prove native improvement. |
| iOS captured output gap | **unmeasured** | **unmeasured** | No iPhone, simulator, Apple SDK or AVFoundation build available. |
| Android captured output gap | **unmeasured** | **unmeasured** | No Android device/emulator/SDK available. |

The updated real-audio smoke target runs seven cases for each of **Alafasy,
Husary and Shaatree** (21 total), including short ayahs, Bismillah, repeats and
Surah Queue. Warm all recordings with networking available, then run with both
`AUDIO_SMOKE_REAL=true` and `AUDIO_SMOKE_OFFLINE=true`. The offline guard rejects
any cache-miss network request and reports/fails on attempts. Also disable device
internet access. The default generated nine-case suite remains available.
Neither real native suite was run on mobile hardware in this environment.

## Why a decoded streaming replacement was not adopted

The existing engines already have native gapless paths; a concrete Darwin
preparation defect was found before establishing whether independent MP3 output
still fails with that defect removed. Approach B would require a new native PCM
streaming backend rather than concatenated MP3 bytes or successions of temporary
WAV chunks. It would need all of the following before adoption:

- iOS `AVAssetReader` decoding plus scheduled continuous `AVAudioEngine` buffers;
  Android `MediaCodec` decoding plus an uninterrupted `AudioTrack` writer.
- Bounded producer/consumer buffers, resampling/channel conversion, decoder reuse,
  exact sample occurrence timelines and seeks, and codec-metadata padding rules.
- Integration with the one authoritative controller, background audio sessions,
  interruptions, route changes, pause/resume, repeat/queue occurrence identities
  and Journey accounting on both platforms.
- Real startup, battery, thermal, memory, disk and output-boundary measurements.
  Platform APIs could avoid a new media-library licence; using FFmpeg or another
  decoder in the app would require a separate dependency/licensing assessment.

None of that backend has been validated here. The plan explicitly requires the
existing implementation as the safe fallback and forbids shipping a more complex
unverified replacement. Therefore the current EveryAyah native path is retained,
with the narrow queue-preparation fix; no speculative PCM backend, full-surah
startup wait, decoded cache, extra player or internal file-chunk transitions ship.

## Performance, behavior and outstanding acceptance

Production startup/download/storage behavior is unchanged apart from asynchronous
retired-cache cleanup in the first commit. The native fix uses an ephemeral
bounded desired-item array and preserves the existing native window; it adds no
long-lived decoded buffer or disk data. Existing app caches, all 22 reciters,
Bismillah rules, controls, repeats, Surah Queue, highlights/page following,
interruptions and Journey remain on the original controller. Generated probe
files are developer-only, outside permanent recitation/offline storage.

C tests exercise the exact production common-prefix helper and suffix operation
order, including exhaustive small sequences and repeat identities. They run with
ASan/UBSan; leak detection is disabled under this sandbox's ptrace restrictions
(the test allocates no heap data). These checks do not compile AVFoundation or
exercise an Apple decoder. The Flutter suite does not compile the Darwin plugin.
Before release, build on macOS and test the patch on iOS, then capture baseline
and candidate output on both physical platforms over speakers and a controlled
wired route. Retain captures, device/OS, codec/format, source hashes and route
metadata; compare the same reciters/short and long ayahs and unsplit control.

**The approximately 100 ms audible switching gap is not yet proven eliminated.**
No omitted/overlapped recitation is introduced by content edits because there are
none; actual native waveform continuity, including route changes/background
behavior, remains a hardware acceptance check. Do not equate the passing tests
or reduced queue operations with a measured zero-millisecond output gap.

## Validation completed here

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: all **395** tests passed, including
  existing short/long cached recordings, lookahead, repeats, interruptions,
  highlights, native source retention and reader layout regressions.
- Three new Python split-signal/analyzer tests and all three existing source
  diagnostic tests passed. The generated unsplit control also aligned at zero
  additional frames with correlation above 0.99999.
- C native-prefix regression passed with `-Wall -Wextra -Werror` and ASan/UBSan,
  exercising 970 prefix/suffix cases. This is not an AVFoundation build.
- Python scripts compile, and staged/unstaged `git diff --check` is clean.
- Native iOS/Android builds, captures, battery measurements and physical-device
  controls/interruptions remain unperformed; no matching devices/SDKs are present.
