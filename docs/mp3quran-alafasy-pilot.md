# MP3Quran Alafasy / Al-Mulk pilot — verification blocked

Investigated on 7 November 2026 from `85f544f` on `v5`. The updated scope is
EveryAyah reciter ID `alafasy`, Full Surah mode, surah 67, all 30 ayahs, with
whole-surah repetition. Ranges, playlists and individual-ayah repeat remain
outside the proposed pilot.

## Decision

The required recording/timing verification could not be completed. Following the
task's explicit fallback instruction, **EveryAyah remains the only playback
path**. This change records the investigation; it does not add or enable a
continuous provider, a runtime feature flag, a staging dependency or UI changes.
The requested continuous-playback implementation is blocked, not delivered.

The [structured findings](mp3quran-alafasy-pilot-verification.json) distinguish
unavailable evidence from a verified negative result. No timestamp, duration,
SHA-256 or read ID is guessed.

## Recording and API evidence

| Source | Observed result | What remains unverified |
| --- | --- | --- |
| [Official Al-Mulk page](https://www.mp3quran.net/eng/afs/67) | Web-readable page names Mishary Alafasi, Hafs 'an Asim, and lists verses 1–30. | Independent speaker identification and the audio contents. |
| [Specified recording](https://cdn.mp3quran.net/audio/mishary-alafasy/r1/067.mp3) | [CDN directory](https://cdn.mp3quran.net/audio/mishary-alafasy/r1/) lists `067.mp3` at 7,293,947 bytes. This is a web index observation, not a local file measurement. | Actual file bytes, SHA-256, duration, clean decoding and all 30 recited ayahs. |
| [Surah metadata](https://api-staging.mp3quran.net/v4/recitations/mishary-alafasy/r1/surahs/67) | Executor request rejected by its outbound proxy with CONNECT 403; web fetch also unavailable. | Live response, recitation version, original-file URL, hash, duration and timing availability. |
| [Ayah timings](https://api-staging.mp3quran.net/v4/recitations/mishary-alafasy/r1/surahs/67/ayah-timings) | Web fetch unavailable; the host is excluded from executor network policy. | Complete, ordered intervals for ayahs 1–30, prologue and exact-file binding. |

The official page's Download link points to
`https://cdn.mp3quran.net/download/audio/mishary-alafasy/r1/067.mp3`. The web tool
encountered `audio/mpeg` there but cannot return playable binary contents. That
does not establish byte equality with the specified `/audio/` URL.

The [v4 documentation](https://docs-staging.mp3quran.net/) describes
`files.original` hashes and sizes, `duration_ms`, completeness and millisecond
ayah tuples. `include=audio` supplies the file identity attached to timings;
those hashes must agree with the downloaded file. It documents ayah 0 as
Bismillah and -1 as isti'adhah, but their presence in **this** recording is
unknown. The examples describe other recordings and are not pilot fixtures.

A stable production v4 service was **not confirmed**. A web probe of
`https://api.mp3quran.net/v4` was inaccessible; that is not proof it does not
exist. No guessed production hostname or staging fallback is installed in the
app. The v3 documentation's Al-Ajamy/read-5 example does not identify this
Alafasy CDN recording, and no v3 timing set was substituted.

## Access blocker

The managed environment reports an enforced restricted outbound policy with no
MP3Quran hosts allowed. Requests with network access enabled still received
proxy CONNECT 403 for both `api-staging.mp3quran.net` and `cdn.mp3quran.net`.
The proxy rejected the connection before an upstream HTTP response or MP3 body
was obtained; this does **not** establish that MP3Quran itself is unavailable.

The requested environment-setting additions are `cdn.mp3quran.net` and
`api-staging.mp3quran.net`, plus `mp3quran.net` and `www.mp3quran.net` for the
official site and established v3 API. Refresh policy status after they are
applied, then make new connections. Any redirect host must be reviewed against
the same policy. Do not work around the allowlist through mirrors or proxies.

Once accessible, capture the two requested JSON responses and also fetch
`/v4/recitations/mishary-alafasy/r1/surahs/67/ayah-timings?include=audio,summary,segments`
to check the timing/audio binding. Download the exact specified original MP3,
verify its hash and length against both responses, and decode the whole file
with FFmpeg. Preserve raw responses and their retrieval dates for review.

## Remaining verification and implementation

Before adding an opt-in development provider:

1. Confirm Alafasy's recitation code, Hafs version, original URL and SHA-256 from
   actual responses. Verify the timing response names that exact file.
2. Validate all 30 numbered ayahs exactly once, integer nonnegative timestamps,
   increasing nonoverlapping intervals, positive durations and bounds within
   the decoded recording. Review gaps/prologue/tail explicitly; do not stretch
   intervals to invent coverage. Confirm any Bismillah/isti'adhah intervals.
3. Audit every interval against the recording, including opening, middle and
   ending boundaries. Structural validity alone does not establish accuracy.
4. Add a separate hash-bound MP3Quran cache and a default-off experimental
   provider for this exact selection, using the existing controller/player.
   Keep release builds disabled until data, rights and device checks pass.
5. Wire position-based occurrence/highlight/statistics updates and timestamp
   seeks without replacing the one continuous source. Whole-surah repeats seek
   to zero; all other selections/repeat modes keep EveryAyah. Preparation and
   failure handoff must use existing session/intent cancellation protections.
6. Add the requested continuous-provider integration regressions using the
   verified recording/timing identity, then compare the entire surah against
   EveryAyah on iPhone and Android. No devices for either platform are attached;
   `flutter devices --machine` currently lists Linux only.

## Usage and offline caching

The official site offers downloads and the API documentation describes cache
headers and bulk manifests. Those facts alone do not establish third-party app
redistribution/offline-caching permission. The API reference's `UNLICENSED`
label is not an audio licence. No applicable audio grant was verified; attempts
to read the official privacy/contact pages returned web-fetch 403 responses.
Confirm the applicable terms or obtain explicit permission before production
release. No outreach was sent and no audio is redistributed by this change.

## Validation

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: all **392 existing tests passed**.
- `git diff --check` and the staged whitespace check: clean.
- Structured report parses as JSON.

Continuous-source, timestamp, offline, repeat, interruption and fallback behavior
have **not** been implemented or validated. No new continuous-provider tests are
claimed. The existing passing suite does not certify this unverified pilot.
