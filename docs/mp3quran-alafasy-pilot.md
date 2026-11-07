# MP3Quran Alafasy / Al-Mulk development pilot

Updated 7 November 2026, based on `f430991` on `v5`.

The exact-file timing snapshot has now passed an **automated Arabic content
review** and is bundled for opt-in development playback. Release builds still
block the pilot and omit the new source indicator entirely. No runtime staging
API dependency is introduced. Human listening and physical-device comparisons
remain outstanding; this is not a production timing certification.

## Test it in development

```sh
flutter run --dart-define=EXPERIMENTAL_MP3QURAN_AL_MULK=true
```

Select **Mishary Alafasy → Al-Mulk → Full surah**, with whole-surah/range repeat.
Open the existing audio modal to see the installed source:

- **MP3Quran (continuous)**: the single original recording was successfully
  installed in the native player after integrity and duration checks.
- **EveryAyah (normal)**: the native EveryAyah source was installed normally,
  including other reciters/surahs, ayah ranges, ayah repeat and Surah Queue.
- **EveryAyah (fallback)**: an opted-in eligible request could not supply or play
  continuous audio, and EveryAyah has actually been installed instead. This
  reason survives pause/resume, repeat and navigation in the same playback plan.
- **No active source**: no source for the active session has been installed yet,
  or playback stopped/completed. A pending download is not labelled MP3Quran.

The indicator follows explicit native installation/handoff state, independently
of the modal's edited selection. Changing Full Surah to Range without pressing
Play cannot change the source label. New playback clears the old fallback reason;
late cancelled preparation cannot publish a provider. Both the label and its
spacing are compiled out of release UI. The indicator is available without
opting into the pilot, so normal EveryAyah playback can also be inspected.

## Recording and API evidence

The [structured report](mp3quran-alafasy-pilot-verification.json) and
[evidence directory](mp3quran-alafasy-evidence/) preserve API responses, response
headers, FFprobe results, signal observations and the new content audit. No MP3
or speech model is committed.

| Source | Verified result |
| --- | --- |
| [Original MP3](https://cdn.mp3quran.net/audio/mishary-alafasy/r1/067.mp3) | HTTP 200; **7,293,947 bytes**; SHA-256 `ded3b53cfc22c3544170f222068472174e200f5958b35561d298bb4db7e54f11`, exactly matching `files.original`. |
| [v4 metadata](https://api-staging.mp3quran.net/v4/recitations/mishary-alafasy/r1/surahs/67) | HTTP 200; catalogue version 668; original URL matches; metadata duration 455000 ms. Other encodings are not used. |
| [v4 timings](https://api-staging.mp3quran.net/v4/recitations/mishary-alafasy/r1/surahs/67/ayah-timings) | HTTP 200; catalogue version 668; complete, ordered, nonoverlapping ayahs 0–30, within the measured MP3 duration. |
| [Timing query with audio/summary/segments includes](https://api-staging.mp3quran.net/v4/recitations/mishary-alafasy/r1/surahs/67/ayah-timings?include=audio,summary,segments) | HTTP 400: only `text` is accepted. No separate timing-response audio hash was returned. |
| [Production v4 candidate](https://www.mp3quran.net/api/v4/recitations/mishary-alafasy/r1/surahs/67) | HTTP 404; stable production v4 remains unconfirmed. |
| [Published timing schema](https://www.mp3quran.net/api-doc/timing_api_openapi.json) | Production v3 and deprecated `/api` are listed; no production v4. |
| [v3 timing reads](https://www.mp3quran.net/api/v3/ayat_timing/reads) | Read 5 is Ahmed Al-Ajamy. Its timings differ and are never substituted. |

The full original MP3 decodes without FFmpeg errors. FFprobe reports
455.444878 seconds, 128 kb/s, 44.1 kHz stereo, Al-Mulk / Mishary Alafasi metadata.
The manifest uses **455445 ms** (rounded measured duration), not the metadata's
rounded-down 455000 ms. Runtime checks verify the full SHA-256 and byte count
before source preparation and reject a decoded-duration difference over 1 s.

## Exact-file timing/content review

[content-audit.json](mp3quran-alafasy-evidence/content-audit.json) records the
MP3 hash, model component hashes, model/package version, expected text, every
unaltered transcript, clip boundaries and review decisions. The script is
[tool/audit_mp3quran_timings.py](../tool/audit_mp3quran_timings.py).

The model was the official sherpa-onnx multilingual Whisper **small int8**
encoder/decoder, using Arabic, greedy decoding and **no text prompt**. FFmpeg
converted the hash-verified MP3 to mono 16 kHz. Each exact v4 interval was cut
from this decoded audio and independently transcribed; these are not transcripts
from another recording. Expected text came from this repository's Uthmani Quran
database. All **30 numbered cuts identified the expected ayah**, and the exact
Bismillah cut recovered `بسم الله الرحمن الرحيم`. Normalized character similarity
was **0.8852–1.0**; substitutions and hallucinated numeric annotations remain
visible in the evidence and were not silently corrected.

Five longer clips crossing actual supplied boundaries recovered the preceding
ayah's ending and the following ayah in the right order:

| Boundary | Supplied previous end / next start |
| --- | --- |
| Bismillah → 1 | 13.718 / 13.865 s |
| 1 → 2 | 24.086 / 24.680 s |
| 14 → 15 | 206.188 / 206.570 s |
| 15 → 16 | 221.590 / 221.801 s |
| 29 → 30 | 437.238 / 437.630 s |

Initial short boundary clips sometimes omitted one side in ASR. The final audit
uses the last up to 8 seconds of the preceding interval plus the entire next
interval, capped at 30 seconds. The script reproduces these final clips. This
checks content across the opening, middle and ending without deriving or moving
any timestamp. Prior signal checks also show pauses close to the Bismillah/1,
1/2, 8/9 and 29/30 boundaries, plus final silence near ayah 30's end.

The 0–7.265 s prologue transcribed as isti'adhah, but v4 supplies no -1 interval.
It stays **unlabelled** at runtime. Ayah 0 is Bismillah at 7.265–13.718 s; ayah 1
starts at 13.865 s; ayah 30 is 437.630–454.358 s. Half-open intervals leave
prologue, gaps and tail without a numbered highlight. No estimated, stretched,
offset or alternate-file timings are used, and no EveryAyah Bismillah is overlaid.

This establishes exact-file verse identity and boundary-content consistency for
development testing. **ASR can omit/hallucinate words, and this model does not
produce independent word timestamps. No human listening, independent speaker
identification or millisecond boundary-error measurement is claimed.** Preserve
the release guard until human/device comparison establishes acceptable highlighting
and native seek behavior across the entire surah.

To reproduce, install `sherpa-onnx` and `soundfile` in a temporary Python virtual
environment, download the official model URL recorded in the audit, and run:

```sh
python tool/audit_mp3quran_timings.py \
  --audio /path/to/067.mp3 \
  --model /path/to/sherpa-onnx-whisper-small \
  --output /tmp/al-mulk-content-audit.json
```

The script rejects an MP3 that differs from the captured original hash/size and
never generates or adjusts timings. Its optional boundary-only rerun also checks
that cached interval transcripts have the same audio, model, catalogue and cuts.

## Provider isolation and release restrictions

`Mp3QuranRepository` remains separate from `AudioRepository`. The full MP3 cache
is `mp3quran/mishary-alafasy/r1/<sha256>/067.mp3`. Downloads are verified before
atomic publication; cached files are rehashed on subsequent preparation.
EveryAyah cache paths are unchanged.

The controller uses one existing `just_audio` player and one source for the
whole surah, shares background/lock-screen controls and interruption handling,
and does not simultaneously download the 30 EveryAyah recordings. Real playback
position drives highlighting, metadata and interval-relative Journey statistics.
Next/Previous seek inside this source, including while paused. Finite/infinite
whole-surah repeats seek back to zero without replacing the source.

Failure stops the single player before installing EveryAyah, retaining selection,
pause intent and repeat cycle. Playback failure restarts the current numbered
ayah at its EveryAyah beginning; different recordings cannot share seek offsets.
A failure seeking at EOF hands off at the next cycle's opening. Stop/replacement
cancels late autoplay and source-indicator updates.

`Mp3QuranPilot.enabled` still requires a non-release build **and** the opt-in
Dart define. `verifiedManifest` is independently **null in release builds**, even
if the define is passed. The snapshot is local; no app request relies on staging.
Other selections and all default builds keep EveryAyah.

## Before production release

- Manually compare the entire surah against EveryAyah on physical iPhone and
  Android, including beginning/middle/end highlighting, offline restart,
  background/lock-screen navigation, interruptions and finite/infinite EOF seeks.
  Only Linux is attached here; neither mobile comparison was performed.
- Review applicable audio and offline-caching rights. The [official rights page](https://www.mp3quran.net/eng/privacy)
  states: “All rights are available to everyone, and we allow any visitor or
  developer to copy any material or use any link on the websites.” No more
  specific third-party offline-caching terms were verified; no outreach was sent.
- Review accuracy evidence and any discrepancies before removing either release
  guard. An opt-in development success is not a release approval.

## Regression validation

The existing pilot regressions cover integrity/cache reuse offline, corruption,
cancellation, all synthetic interval edges, Bismillah, page following,
Next/Previous, repeats, Journey, interruptions and automatic fallback. New tests
check the bundled manifest against the captured content audit, provider labels
only after native installation, paused fallback, navigation, selection-only edits,
missing manifests, fresh playback and stale preparation. Product-constant tests
explicitly check that the indicator and pilot remain disabled with the opt-in flag.

Validation on 7 November 2026:

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: **428 passed**; the two
  mode-specific tests are skipped in the default run.
- `flutter test --no-pub test/audio_source_release_test.dart
  --dart-define=EXPERIMENTAL_MP3QURAN_AL_MULK=true`: development opt-in passed.
- The same test file with both `--dart-define=dart.vm.product=true` and the
  pilot flag: product guard passed (indicator hidden, pilot off, manifest null).
- `git diff --check` and staged whitespace check: clean.
- All evidence JSON parses; the Python audit script passes `py_compile`.

The flag tests exercise compile-time product constants in the test engine;
they are not physical-device release testing.
