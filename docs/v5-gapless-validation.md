# v5 audio boundary investigation

This follow-up starts at `a4fa802`. It preserves the bounded native playlist and
all Bismillah, repeat, recovery, offline, highlighting and statistics behavior.

## Findings and changes

A reproducible preparation bottleneck existed in `AudioRepository`: even a valid
cached recording entered the two-worker download scheduler. If both workers were
waiting on network I/O, cached Bismillah/ayah requests also waited. Before the fix,
the four-reciter regression timed out after 500 ms with both requests deliberately
blocked; the wait would last until a worker became free. This demonstrates an
application preparation delay, **not an output-measured audible gap**.

Cache checks now run independently of network workers. Consumers join a shared
recording job before asynchronous cache validation, preserving deduplication and
independent cancellation. Only cache misses enter the two-worker network queue.
Cancellation uses one weakly keyed broadcast watcher per session token; finished
cache reads remove their listeners instead of retaining a callback per repetition.
MP3 validation and Bismillah SHA-256 checks remain mandatory on cache hits. Files
are rechecked at acquisition to cover cache changes during lookup.

Moving Next/Previous within a selection now invalidates occurrence callbacks and
the native window while retaining in-flight recording acquisitions. This prevents
cancelling and downloading the same received file again before its atomic cache
publication finishes. Stop, replacement, recovery and disposal retain their
cancellation behavior. Network concurrency stays at two, with one background
worker maximum. Native sources stay bounded at six and the forward window stays
at three upcoming occurrences. Ordinary prepared boundaries still use automatic
native index changes, with no application pause, stop, seek or source-list reload.

Recording content is another measurable source of boundary quiet. It differs
between reciters and remains present even after FFmpeg honors available gapless
metadata. The measurements below do not prove a native player defect. No new
player, transcoding, runtime scanning, clipping, crossfade, silence skipping,
speed/pitch change or audio-cache rewrite is introduced.

## Reproducing recording measurements

Run from the repository root with Python 3, FFmpeg and ffprobe on PATH:

```bash
python3 tool/audio_gap_diagnostic.py --manifest tool/audio_gap_samples.json --output /tmp/audio-gap-analysis.json
python3 -m unittest discover -s tool -p test_audio_gap_diagnostic.py -v
```

For other local recordings, pass their paths in playback order instead of the
manifest. The tool is read-only and refuses an output path that would overwrite
an input. The committed [sample manifest](../tool/audio_gap_samples.json) records
original EveryAyah folder/filename, mirror archive URL and SHA-256. The 37 numbered
recordings match the mirror's upstream checksum state; the four canonical
Bismillah files also match the production content audit. Direct EveryAyah access
is not available in this environment. The corpus is from the recorded maqra
mirror revision `cf6f004bfb5fa24017db479d39676a4a908f518a`.

The [full results](audio-gap-analysis.json) contain **41 recordings and 41
boundaries**, including Bismillah → ayah 1, all consecutive ayahs of Al-Ikhlas
and Al-Falaq, the last ayah of Al-Ikhlas → the next Bismillah, and a longer
Al-Fatihah 1:7 repetition. Minshawy's sampled 1:7 lasts **34,847.347 ms** in decoded
PCM. Results include exact digital-zero edges and -90/-75/-60/-45 dBFS peak edges,
container/PCM duration, Xing/Info/LAME hints, ffprobe skip/discard side data, sample
rate and channel count. PCM is decoded at its original rate with every channel
retained. Taking peak across channels avoids mistaking antiphase stereo for
silence; a single sample above the threshold ends an edge.

The following are **source PCM quiet intervals**, calculated as the earlier
file's contiguous trailing edge plus the next file's contiguous leading edge.
They are not audible-output measurements or safe automatic trim instructions.

| Reciter | Al-Ikhlas consecutive ayahs: exact zero (ms) | Same boundaries below -60 dBFS (ms) | Last Al-Ikhlas ayah → next Bismillah below -60 dBFS (ms) | Metadata in sampled files |
| --- | --- | --- | --- | --- |
| Mishary Alafasy | 0 | 12.608–20.385 | 159.229 | Xing/Info + LAME; FFmpeg skip/discard hints |
| Al-Husary | 39.206 | 49.546–51.542 | 249.161 | No Xing/Info or FFmpeg skip/discard hints |
| Abu Bakr Ash-Shaatree | 39.206 | 44.490–44.943 | 45.147 | No Xing/Info or FFmpeg skip/discard hints |
| Al-Minshawy Mujawwad | 13.084–26.145 | 16.599–30.726 | 326.304 | No Xing/Info or FFmpeg skip/discard hints |

For example, Alafasy's `112001.mp3` contains LAME delay/padding values of
576/2,113 samples. FFmpeg reports 1,105 skip samples and 1,584 discard samples,
including its decoder-priming convention. These hints are already applied in the
reported PCM; subtracting them again would risk clipping. Missing hints do not
prove zero encoder delay or identify precisely how each native decoder handles
priming. The digital-zero intervals in the other samples are padding candidates,
not a corpus-wide diagnosis. Low-level edges and larger surah-boundary pauses can
also include breath, room tone, vocal decay or deliberate pauses.

No automatic trimming is approved. An amplitude threshold alone cannot identify
Arabic pronunciation or intentional pause boundaries, and FFmpeg edge positions
cannot be assumed identical to native decoder output for untagged MP3s. Keeping
those recordings intact is the conservative fallback required by this task.
Original fixture/cache hashes are unchanged, so all source-content measurements
are identical before and after the scheduling fix.

## Native implementation review

Android uses Media3 **1.4.1** progressive MP3 sources with default extractor flags.
The app has not disabled metadata and uses the default disabled-offload path.
Upstream [Mp3Extractor](https://github.com/androidx/media/blob/1.4.1/libraries/extractor/src/main/java/androidx/media3/extractor/mp3/Mp3Extractor.java)
reads gapless information from ID3/Xing/LAME and puts encoder delay/padding in the
format. [DefaultAudioSink](https://github.com/androidx/media/blob/1.4.1/libraries/exoplayer/src/main/java/androidx/media3/exoplayer/audio/DefaultAudioSink.java)
passes those values to `TrimmingAudioProcessor` on the PCM path. The wrapper
passes original files to that machinery. No missing metadata flag was found to
fix, and no duplicate application-level trimming was added.

Darwin uses `AVURLAsset`/`AVPlayerItem` and `AVQueuePlayer` automatic item advance.
Original MP3 metadata is retained; there is no custom wrapper-level gapless parser.
Queue edits preserve the current player item but can rebuild upcoming treadmill
items. The ordinary completion path resets the **ended** item for reuse, rather
than seeking the active next item to advance playback. Whether these details add
output latency or AVFoundation honors every sampled MP3 tag needs native capture.
The precise-duration option alone is not evidence of an audible-gap fix. No
speculative ExoPlayer/AVFoundation or vendored-player patch was made without an
output-measured regression. Existing bounded-registration/native-cache patches
remain intact.

## Regression and device validation

Four-reciter tests use actual production Bismillah and numbered MP3 bytes. They
cover cached lookahead while both network workers are blocked, native automatic
Bismillah/ayah/Surah Queue transitions, both repeat modes, long-ayah infinite
repeat, pause/stop during an outstanding append, seek/resume position, lock-screen
metadata, bounded sources, and unchanged original hashes. The existing suite
continues covering 2,500 transitions, the real Dart source registry over 1,000
removals/appends, delayed/missing downloads, corrupt audio recovery, automatic
saving, cancellation/replacement, all production mappings and listening statistics.
Python diagnostic tests cover stereo cancellation, quiet decay, known source
silence, metadata-aware MP3 decoding without double trimming, integrity and
refusal to claim native-output latency.

Final checks: `flutter analyze --no-pub` reports no issues; `flutter test --no-pub
--reporter expanded` passes all **357 tests**; the three Python diagnostic tests
pass, and `git diff --check` is clean. No native-output gap is inferred from these
checks.

Only Linux is available in `flutter devices --machine`; no Android/iOS device or
emulator is connected. **Native output gap before/after: unmeasured (not 0 ms).**
The cache scheduling regression is fixed, but these tests do not certify audible
gaplessness or quantify how much of a user's tiny pause remains on their device.

For output measurements, use the [native diagnostic](../tool/audio_repeat_smoke.md)
on Android and iOS at speed 1, with crossfade/silence skipping disabled. Capture
lossless output through a trusted device loopback or wired interface at a known
sample rate. First use the generated fixture with known 40 ms head/60 ms tail
silence to calibrate the capture and detect native additions. Then capture these
exact hash-matched real clips, align the non-silent waveform on each side of a
boundary, and compare captured edge-to-edge time with decoded source edge quiet.
Report total captured quiet, source quiet and their difference separately, along
with route/device/OS, codec format and measurement uncertainty. Preserve natural
pauses in the reference. A microphone's room noise, Bluetooth buffering, clock
drift and output resampling can confound subtraction. Repeat short ayahs,
Bismillah boundaries, surah transitions and repeats before/after on the same route.
Index-event timestamps and simulated elapsed time are not substitutes for this
PCM-output measurement.
