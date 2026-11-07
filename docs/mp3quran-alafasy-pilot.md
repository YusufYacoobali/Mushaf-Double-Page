# MP3Quran Alafasy / Al-Mulk experimental pilot

Updated 7 November 2026 on `v5`, based on `a371881`. The earlier network-policy
blocker has been resolved. The isolated provider is implemented and tested with
synthetic fixtures, but **real-recording playback remains disabled**: an accurate
content/timing audit and the required mobile comparisons are not complete.
EveryAyah remains the production and default development playback path. Reader
UI and the latest iPhone layout files are unchanged.

## Recording and API verification

The following requests succeeded on 7 November 2026. Captured JSON (formatted
for review), selected response headers, FFprobe output and signal observations
are in [mp3quran-alafasy-evidence](mp3quran-alafasy-evidence/).
The [structured report](mp3quran-alafasy-pilot-verification.json) records scope
and verification limits. No MP3 is committed or redistributed.

| Source | Result |
| --- | --- |
| [Requested original MP3](https://cdn.mp3quran.net/audio/mishary-alafasy/r1/067.mp3) | HTTP 200; **7,293,947 bytes**; SHA-256 `ded3b53cfc22c3544170f222068472174e200f5958b35561d298bb4db7e54f11`. Both exactly match `files.original` metadata. |
| [v4 surah metadata](https://api-staging.mp3quran.net/v4/recitations/mishary-alafasy/r1/surahs/67) | HTTP 200; catalogue version 668; original URL is the requested CDN URL; `duration_ms: 455000`; also offers different 64k MP3 and Opus files, which this pilot never selects. |
| [v4 ayah timings](https://api-staging.mp3quran.net/v4/recitations/mishary-alafasy/r1/surahs/67/ayah-timings) | HTTP 200; catalogue version 668; `complete: true`; ayahs 0–30 exactly once, ordered and nonoverlapping, all within the MP3 duration. |
| [Extended timing query](https://api-staging.mp3quran.net/v4/recitations/mishary-alafasy/r1/surahs/67/ayah-timings?include=audio,summary,segments) | HTTP 400; `Unsupported include; the allowed value is text.` Contrary to the earlier investigation's expectation, this request does **not** return timing-specific audio hashes. |
| [Production v4 candidate](https://www.mp3quran.net/api/v4/recitations/mishary-alafasy/r1/surahs/67) | HTTP 404. No stable production v4 endpoint confirmed; this is not proof no other endpoint exists. |
| [Published timing documentation](https://www.mp3quran.net/eng/timing-api) and [OpenAPI schema](https://www.mp3quran.net/api-doc/timing_api_openapi.json) | HTTP 200; schema lists production `https://mp3quran.net/api/v3` and deprecated `/api`, not production v4. |
| [v3 timing reads](https://www.mp3quran.net/api/v3/ayat_timing/reads) | Read **5 identifies Ahmed Al-Ajamy**, not Alafasy. Its surah-67 timestamps differ from the v4 recording. None are substituted. |

`ffprobe` measured **455.444878 seconds**, 128 kb/s MP3, 44.1 kHz stereo, with
Al-Mulk / Mishary Alafasi metadata. Metadata duration is rounded down by about
445 ms. A complete FFmpeg audio decode (`-map 0:a:0 -f null -`) exited 0 with
no errors. These checks establish file identity and decodability, not an
independent speaker/content audit.

## Timing accuracy and the activation blocker

The v4 response labels Bismillah (ayah 0) at **7.265–13.718 s**, ayah 1 at
**13.865–24.086 s**, ayah 15 at **206.570–221.590 s**, and ayah 30 at
**437.630–454.358 s**. It leaves 0–7.265 s unlabelled and does not supply an
isti'adhah (-1) interval for this recording. That opening's contents have not
been independently established. Gaps and the final tail must never be assigned
invented ayah timestamps.

FFmpeg `silencedetect=noise=-35dB:d=0.1` on this exact MP3 found, for example:

- A pause at 13.563–13.934 s near the supplied Bismillah/ayah-1 boundary.
- A pause at 24.350–24.675 s near the supplied ayah-1/2 boundary.
- A pause at 129.699–129.810 s near the supplied ayah-8/9 boundary.
- A pause at 437.402–437.638 s near the supplied ayah-29/30 boundary.
- Final silence beginning at 454.337 s near the supplied ayah-30 end.

Signal pauses support plausibility but cannot prove the recited verse identity,
Bismillah, or accurate beginning/middle/end highlighting. **No human listening
or ASR content validation is claimed.** The exact v4 metadata path and file hash
are verified; the timing response itself supplies no independent hash binding.
The captured intervals remain review evidence, not runtime timings. No verse
length estimates, offsets, stretched intervals or alternate-file timings are used.

## Isolated implementation

- `Mp3QuranRepository` is separate from `AudioRepository`. It downloads the
  fixed original URL into `mp3quran/mishary-alafasy/r1/<sha256>/067.mp3`, validates
  byte count and SHA-256 on **every preparation**, and atomically publishes a
  verified download. Cache corruption, cancellation and offline reuse are tested.
  EveryAyah paths and files are unaffected.
- `Mp3QuranPilot.enabled` requires the default-off Dart define
  `EXPERIMENTAL_MP3QURAN_AL_MULK=true` and a non-release build. Additionally,
  `verifiedManifest` is intentionally **null**. The flag alone cannot activate
  the unaudited recording. Only Alafasy + surah 67 + Full Surah + range repeat
  qualifies; ranges, individual-ayah repeats and Surah Queue use EveryAyah.
- The controller's small continuous extension shares its sole `just_audio`
  player, background handler, pause intent, cancellation guards and Journey
  tracker. Preparation automatically starts one cached source. It never
  prepares/appends 30 EveryAyah sources in parallel. Ayah changes update logical
  state/metadata from real position; they do not load another source.
- Intervals are half-open. Ayah 0 is an introduction with no numbered highlight
  or numbered Journey credit. Prologue, inter-ayah gaps and tail have no numbered
  highlight. Next/Previous seek inside the same file, including while paused.
  Previous at ayah 1 stays at ayah 1; Next at ayah 30 respects finite/infinite
  cycle navigation. Whole-surah repeats pause and seek to zero without reloading
  a queue. Repeat counters remain logical, independent of the one native item.
- Journey uses interval-relative position and duration, so a numbered listen
  needs 90% of that interval. Introduction time counts as time, not an ayah.
  The existing handler routes app, notification, Bluetooth and interruption
  commands to this same controller; interruption end does not resume by itself.
- Preparation, integrity, decoded-duration, decoder and seek failures stop the
  sole player before installing EveryAyah, preserving selection, pause intent
  and repeat cycle. During playback the current numbered ayah restarts at its
  EveryAyah beginning: offsets from different recordings cannot be carried over.
  Stop/replacement invalidates late preparation and autoplay.

## Required before activation / production

1. Audit the actual MP3 against **every** supplied interval, particularly the
   unlabelled opening, Bismillah and boundaries across the beginning, middle and
   end. Record reviewer/method and evidence linking the audit to the SHA-256.
   If intervals are inaccurate, keep the pilot disabled; never estimate fixes.
2. Only after a successful audit, bundle an immutable `Mp3QuranManifest` with
   that hash, full decoded duration and reviewed intervals. Development builds
   can then opt in with the experimental define. Do not add runtime calls to
   staging; a reviewed local manifest works offline.
3. Compare the entire surah against EveryAyah on **physical iPhone and Android**,
   including background/lock-screen navigation, interruptions, offline restart,
   paused navigation, finite/infinite cycles and native EOF seeks. Only Linux
   is attached here (`flutter devices --machine`); neither mobile comparison
   was performed. Unit tests do not demonstrate smoother real-device playback.
4. Review applicable rights before releasing or removing the release guard.
   The [official privacy/rights page](https://www.mp3quran.net/eng/privacy),
   accessible HTTP 200, states: “All rights are available to everyone, and we
   allow any visitor or developer to copy any material or use any link on the
   websites.” This is positive usage evidence; no more specific third-party
   offline-caching terms were verified. No outreach was sent.

## Validation

`test/mp3quran_pilot_test.dart` exercises structural/routing gates, autoplay,
verified cache reuse offline, same-size corruption, cancellation, Bismillah,
all 30 synthetic intervals and exact gap edges, page following, Next/Previous,
finite/infinite repeats, Journey listening, pause during download, stale
preparation, interruptions, missing manifests and automatic failure fallback.
Synthetic payloads/timestamps are explicitly not evidence about Quran content.

Validation on 7 November 2026:

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: **422 tests passed**, including
  30 new pilot regressions and all 392 existing tests.
- `git diff --check` and `git diff --cached --check`: clean.
- All committed evidence JSON parses successfully.

The pilot remains disabled until the audit and device checks above establish
the requested success criteria.
