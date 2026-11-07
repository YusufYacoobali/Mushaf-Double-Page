# Yasser Al-Dossari / Ar-Rahman continuous PCM proof

## Delivered scope

Stage A uses **Yasser Al-Dossari (`yasser_dussary`), Ar-Rahman 55:1–10**, once,
with the existing verified EveryAyah Bismillah. It prepares and plays **one WAV
source**, not ten MP3 sources or consecutive joined chunks. EveryAyah remains the
only recording provider. No audio UI changes or alternative timestamp API exist.

This is an explicitly launched **development proof**, not production progressive
streaming. Regular `flutter run` and release builds retain the existing EveryAyah
player. Release rejects proof registration. Unsupported proof selections—including
full surahs, queues, repeat counts greater than one and infinite repeats—use the
regular player in full; they are never shortened to ten ayahs.

The first commit builds/verifies the exact-sample proof; the follow-up integrates
it with the existing controller, Mushaf UI and background command bridge.

## Build from cached originals

On a development computer with Python 3 and FFmpeg, provide a directory holding
the original `055001.mp3` through `055010.mp3` and canonical `001001.mp3` from
`Yasser_Ad-Dussary_128kbps`. This is the same folder/name mapping used by the app's
EveryAyah cache. The builder rejects a Bismillah hash that differs from the
existing content audit. It requires an empty **separate disposable** output directory.

```sh
python3 tool/build_everyayah_pcm_proof.py \
  --cache /path/to/audio/yasser_dussary \
  --output /tmp/yasser_rahman_proof
```

The builder does not download recordings or modify MP3s. It decodes each file with
FFmpeg's normal codec-metadata handling into interleaved signed 16-bit PCM,
44.1 kHz stereo, with conversion by FFmpeg if needed. The checked Yasser files
already have this rate/layout. It streams the complete decoded samples in order
into `continuous.wav` and writes an exact integer sample timeline in `manifest.json`.
No amplitude threshold, quiet trimming, crossfade, overlap, fade, arbitrary offset
or compressed-byte concatenation is used. Missing padding metadata does not grant
permission to remove quiet samples; no manual padding subtraction occurs.

It then independently decodes each original a second time and compares that
entire decoded segment **byte-for-byte** with its assigned WAV segment, including
first/last samples. All boundaries are consecutive: the preceding exclusive end
sample equals the next start sample. The independent verification decode is a
Stage-A audit step, not a repeatedly running app decoder.

## Checked artifact and limitations of its provenance

[everyayah-pcm-yasser-proof.json](everyayah-pcm-yasser-proof.json) records every
original SHA-256, decoded-segment SHA-256, occurrence identity, exact sample bounds,
WAV/PCM hashes, FFmpeg version and preparation measurements. No recitation/WAV
binary is committed.

This environment's review corpus used the original EveryAyah-mapped files from
the previously documented maqra mirror's `yasser-ad-dossari-128kbps/055.zip`, plus
the existing hash-verified Bismillah fixture. Live upstream byte equality was not
independently rechecked; the application source mapping remains
`https://everyayah.com/data/Yasser_Ad-Dussary_128kbps/…`. The builder can be rerun
against the user's actual cached EveryAyah files and derives fresh exact sample
bounds from those bytes; it does not reuse another recording's timings.

An unprompted Arabic Whisper small int8 check of the actual review files recovered
`بسم الله الرحمن الرحيم` from `001001.mp3`, `الرحمن` from `055001.mp3`, and
`علم القرآن` from `055002.mp3`. This supports the separate Bismillah placement;
it is not human listening or an independent all-verse speech audit. The sample
preservation proof compares decoder output directly and does not rely on ASR.

Measured here on Linux:

| Metric | Result |
| --- | --- |
| Numbered ayahs / Bismillah | 10 / 1 |
| Total PCM frames | 2,151,105 |
| Duration | 48,777.891 ms |
| WAV size | 8,604,464 bytes |
| Builder preparation including independent re-decode comparison | 3.003 s |
| Python builder peak RSS | 24,924 KiB; FFmpeg subprocess memory is not included |
| Decoded sample comparison | Every segment byte-for-byte equal |
| Native phone startup, CPU, battery and output gap | **Unmeasured** |

The builder holds one decoded recording in a temporary PCM file, writes in 64 KiB
blocks, and verifies one recording at a time. Temporary decoder files are removed.
The disposable WAV is retained intentionally for repeated device capture/testing,
not registered as a permanent offline recording. Delete the proof directory after
testing; keep the canonical compressed cache. The app hashes the WAV asynchronously
before playback and checks its PCM header, size, frame count and duration.

## Run in the existing app UI

Copy `continuous.wav` and `manifest.json` into `pcm_proof/` under the test app's
application-support directory, or specify an app-readable directory:

```sh
flutter run -d DEVICE_ID -t tool/everyayah_pcm_poc.dart \
  --dart-define=EVERYAYAH_PCM_PROOF_DIRECTORY=/app/readable/pcm_proof
```

If the directory define is omitted, the target uses
`getApplicationSupportDirectory()/pcm_proof`. On Android, use Android Studio Device
Explorer or `adb run-as` for the selected test package. On iOS use an Xcode test
container/simulator copy. Host `/tmp` paths are not automatically readable by a
physical phone. Use a separate test installation to keep diagnostic artifacts and
Journey records isolated. Copy the original MP3s into that installation's normal
`documents/audio/yasser_dussary/` cache too if testing **offline fallback**.

In the unchanged audio modal choose **Yasser Ad-Dussary → Ar-Rahman → Ayah range
1–10 → repeat 1 → repeat range**, then Play. The proof still starts automatically
after verification. The app's default saved repeat count may be 10: change it to 1.
Other selections retain regular playback. Launching `lib/main.dart` normally never
registers the proof, even if the files happen to exist.

## Controller integration

There is still one `QuranAudioController`, one `just_audio` player and the existing
`QuranAudioHandler`. The development target registers the artifact with that same
singleton before launching the ordinary app; no second controller/audio session
competes with it. No native plugin or media-library dependency was added.

While the proof is selected:

- One `AudioSource.file(continuous.wav)` is loaded. Ordinary ayah changes do not
  append, seek, pause, stop or reload a native source. Actual reported native
  playback position selects the half-open sample interval; no verse-length estimate
  is used. UI updates inherit the position stream's reporting/polling granularity,
  not guaranteed per-sample rendering precision.
- Each logical occurrence has surah, ayah (null for Bismillah), cycle 1, exact
  start/end sample and unique identity. The current cursor, display, Mushaf
  highlights and page follower consume those logical updates.
- Next/Previous seek inside the same WAV. Lock-screen positions/durations and
  ordinary seek commands remain relative to the current ayah, translated to the
  WAV's absolute timeline. Buffered metadata is likewise interval-relative.
- Journey samples the interval-relative position and duration; Bismillah counts
  listening time without numbered-ayah credit. Pause/resume retains identity;
  manual navigation creates a new listening occurrence.
- The existing handler keeps lock-screen/Bluetooth commands and pause-on-noisy/
  interruption behavior. Interruption end does not resume by itself.
- Failed verification, duration/readiness, decoder or seek errors stop the one
  source before installing normal EveryAyah at the current logical ayah, retaining
  selection and pause intent. The fallback restarts that ayah at its beginning;
  it does not apply potentially different decoder offsets to the MP3. Stop or
  replacement invalidates late proof setup/autoplay.

No simultaneous EveryAyah MP3 lookahead/download job is started by the proof path.
The prebuilt artifact itself already requires all ten originals; this is explicitly
not the fast progressive producer required for arbitrary selections.

## What is not completed

Stage A has sample-preservation and controller regressions, but **native iOS and
Android audible playback has not been verified**. Only Linux is attached and
neither mobile SDK is installed. No Apple/Android build, output capture, speaker/
headphone comparison, route-change battery test or physical highlighting review
was performed. A single WAV removes per-ayah MP3 source switching architecturally;
it is not proof that a phone's output never underruns.

Stages B/C remain unimplemented: progressive downloading/decoding into one bounded
native PCM renderer, arbitrary long ranges, full surahs, queues, continuously fed
finite/infinite repetitions, decoded-data reuse and production performance
measurements. These continue through the working regular EveryAyah path.
Do not adopt the prebuilt-WAV proof for full-surah startup: it waits for its entire
ten-file preparation and stores a disposable uncompressed test artifact. It must
not be represented as the production solution or a sequence of temporary chunks.

Before expanding, compare the same cached Yasser files through normal playback
and this one-WAV proof on physical iPhone and Android. Capture output and compare
boundaries to the decoded reference, including Bismillah, short ayahs, pause/
resume, seeking, background controls and interruption/failure fallback. Preserve
existing recitation quiet and compare added output delay separately. Only after
that acceptance should a measured bounded AVAudioEngine/AudioTrack (or proven
alternative) producer be integrated; no unverified native-engine rewrite ships.

## Validation

The timeline and controller regressions cover exact boundaries, Bismillah, one
source across all ten ayahs, Next/Previous/seek, Journey, pause/resume, interruptions,
Stop/replacement, verification/decoder fallback and retaining normal playback for
unsupported repeat/full-surah/queue selections. The actual generated 8.6 MB artifact
also passes the app's WAV/hash/timeline validator in a separately invoked test.
Product-constant regression confirms that release refuses registration.

Validation on 7 November 2026:

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: **405 passed**, two mode/artifact
  checks skipped in the default run.
- The artifact test with `EVERYAYAH_PCM_PROOF_DIRECTORY` pointing at the actual
  generated Yasser proof: passed.
- The release-registration check with `--dart-define=dart.vm.product=true`: passed.
- Both Python builder regressions passed; staged/unstaged whitespace checks clean.
- Android debug APK build was attempted with the proof target. Flutter downloaded
  its engine artifacts, then stopped with **No Android SDK found**. No APK was
  built. Only Linux appears in the connected-device list; iOS cannot build here.

No audible phone gap measurement or progressive-production success is claimed.
