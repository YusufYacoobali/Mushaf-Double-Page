# v5 implementation and validation

The later responsive-layout, review-prompt and daily-reminder changes are covered
in [v5 responsive validation](v5-responsive-validation.md).

The audio follow-up starts from `de190cf` on the existing `v5` branch. Later
responsive changes are linked above, and the Tasbeeh simplification is described
below. Nothing is merged into `main`.

The later cache scheduling and recording-boundary investigation is documented in
[v5 gapless validation](v5-gapless-validation.md), including actual PCM measurements
and the limits of native-output testing in this environment.

## Continuous playback queue

`QuranAudioController` remains the single playback controller. It starts when the
first required recording is ready, then incrementally appends prepared sources in
logical order. The target is the current occurrence plus three future occurrences,
with at most one consumed occurrence retained. The hard native limit is six,
including introductions. Download concurrency remains two, with at most one
background request so upcoming playback always has a slot. Requests from playback
and offline saving share physical jobs across independently cancellable consumers.

Normal transitions use just_audio's actual sequence/source events. They do not
pause, stop or replace the playlist. Prefix removal preserves the current source
and position. Each scheduled occurrence has a stable session/occurrence ID, a
separate physical recording ID, surah/ayah or introduction, verse repetition and
range cycle. Future planning uses cursor copies. Repeated recordings can share a
cache file while retaining distinct playback occurrences. Logical Next/Previous
operate on ayahs; Next from an introduction reaches ayah 1.

Finite and infinite verse/range repetitions use the same planner. A new range
cycle starting at ayah 1 includes an applicable introduction; copies of an
individual ayah do not. Sequence events drive highlighting and metadata. Queue
trimming cannot create another listen. Introductions count listening time but
never create numbered-ayah listens.

Completion means the logical plan is finished. If the native queue genuinely runs
out while its next occurrence is preparing, the controller retains that exact
occurrence and shows Buffering/Recovering. Controlled pause/reload is reserved for
that exhaustion, recovery, initial installation or explicit navigation. Pause
intent survives replenishment. Stop and replacement invalidate session work and
background saving. Next invalidates the playback window while preserving the
selection download. Stale callbacks cannot adopt an old occurrence.

A future decoder error is resolved through its reported source index and the
actual native sequence tag. Its suffix is deferred without invalidating or
interrupting a healthy current recording. Repair occurs at its boundary without
consuming a repeat. If the native engine itself becomes idle, the current source
can be reloaded at its saved position without deleting a healthy cache entry.
Preparation has an initial attempt plus up to three exponential-backoff retries;
persistent missing files fail immediately. A separate decoder-restart cap prevents
an endless native failure loop. Retry / Skip ayah / Stop remain explicit choices
for numbered ayahs, which are never silently skipped. A genuinely unavailable
introduction is omitted internally after bounded recovery; a passive notice
reports that it did not play, and ayah 1 still starts.

MP3 validation, atomic temporary-file publication, connection/receive/total
request deadlines, native load deadlines and buffering-stall recovery remain.
Canonical Bismillah hashes validate cached and downloaded introductions, including
offline selection downloads. Original numbered cache paths remain compatible.

### Why just_audio is vendored

The published 0.10.5 Dart registration map and Android MediaSource cache retain
removed sources. A six-item visible playlist alone therefore does not bound
memory during infinite playback. `packages/just_audio` contains the MIT-licensed
0.10.5 package with a small local patch: release unreachable Dart registrations,
preserve the current identity during root prefix removal, and prune Android's
source cache after root removal. See [the patch notes](../packages/just_audio/LOCAL_CHANGES.md).
The regression uses the real Dart player with a controlled native platform,
performing 1,000 incremental removals/appends. Android Java and Darwin native
execution have not been verified on a device here.

## Automatic offline saving

Play starts when the first recording is ready. The complete selected ayah range,
full surah or Surah Queue is then saved in the background in selection order,
including one reusable Bismillah source. Repeated cycles and individual ayah
repetitions do not expand downloads. Current and upcoming playback jobs take
priority over the sequential background sweep; all consumers share physical jobs
and reuse validated cache files. The forward window continues preparing upcoming
items while an earlier download is blocked, without reordering native appends.

The manual Download selection button is removed. A small progress bar and saved
recording count indicate background work, with Cancel saving offline while active.
Selection available offline appears only after all required recordings are valid.
Failures receive bounded retries, later files continue saving, and incomplete
coverage is reported honestly. Cancellation retains completed files and removes
partial files. Replacement and lock-screen Stop cancel old background work;
Pause/Resume and Next/Previous preserve it. Cache invalidation during decoder
recovery refreshes offline availability instead of retaining a stale success.

## Reusable Bismillah content audit — 6 November 2026

**22 of 22 configured reciters have a reusable Bismillah-only source**, enabling
all **112 applicable surahs per reciter (2,464 combinations)**. There is no
per-surah whitelist. Unsupported configured reciters: **none**. A future unknown
reciter without a verified source starts its numbered ayahs directly and reports
the unavailable introduction without prompting or switching voices.

The audit contains 163 actual MP3 clips decoded with ffmpeg and Arabic
transcriptions from sherpa-onnx multilingual Whisper tiny/base/small int8. The
22 chosen MP3s were freshly hash-checked and decoded, then independently
transcribed again with the base model. Each chosen source has an exact normalized
Bismillah-only small or base transcript, and no reviewed transcript identifies
isti‘adhah. This is **automated content review, not human listening or independent
speaker identification**. Source identity comes from the same EveryAyah
reciter/style collection. ASR can omit or hallucinate words; this audit does not
certify every numbered ayah in the collection.

| Reciter | Reused source file |
| --- | --- |
| Mishary Alafasy | `001001.mp3` |
| Abdurrahman As-Sudais | `001001.mp3` |
| Abdul Basit Murattal | `001001.mp3` |
| Abdul Basit Mujawwad | `112000.mp3` |
| Al-Husary | `bismillah.mp3` |
| Abu Bakr Ash-Shaatree | `001001.mp3` |
| Ahmed Al-Ajamy | `112000.mp3` |
| Maher Al Muaiqly | `001001.mp3` |
| Al-Minshawy Murattal | `001001.mp3` |
| Al-Minshawy Mujawwad | `112000.mp3` |
| Hani Rifai | `bismillah.mp3` |
| Ali Al-Hudhaify | `001001.mp3` |
| Muhammad Ayyoub | `001001.mp3` |
| Nasser Al Qatami | `001001.mp3` |
| Yasser Ad-Dussary | `001001.mp3` |
| Saud Ash-Shuraym | `001001.mp3` |
| Abdullah Basfar | `001001.mp3` |
| Saad Al-Ghamdi | `bismillah.mp3` |
| Fares Abbad | `001001.mp3` |
| Abdullah Al-Juhany | `001001.mp3` |
| Ali Jaber | `112000.mp3` |
| Salah Bukhatir | `001001.mp3` |

Ali Jaber's `001001.mp3` contains isti‘adhah as well as Bismillah, so the clean
`112000.mp3` is used. Ash-Shaatree's sampled `SSS000` clips contain isti‘adhah
alone; his clean `001001.mp3` is used. Abdul Basit Murattal's sampled 112/114
introductions include isti‘adhah; his clean `001001.mp3` is used instead. No
unexamined filename is assumed to contain only Bismillah.

Direct EveryAyah requests are blocked by this environment's network policy. The
actual bytes come from the upstream-checksummed public
[maqra mirror](https://github.com/Abdalla-Eldoumani/maqra) at revision
`cf6f004bfb5fa24017db479d39676a4a908f518a`. The app retains original EveryAyah URLs
and checks chosen source SHA-256 values at download/cache access. Live upstream
availability can change; there is no claim of a live availability audit.

[Committed evidence](bismillah-content-audit.json) records original URLs,
transcripts, durations, hashes, manifest matches, provenance, canonical mappings
and fresh verification results. The [source builder](../tool/build_bismillah_audit.py)
reproduces the mappings from that evidence. Actual chosen MP3s are committed as
[test fixtures](../test/fixtures/bismillah/README.md), and tests check all 22 hashes
and exercise the production mappings and real cache/download implementation.

Every applicable boundary is previous surah → Bismillah → new surah ayah 1 →
remaining ayahs, including the first surah and full-queue repeat. Al-Fatihah and
At-Tawbah get no added introduction. Starting after ayah 1 adds none; individual
ayah repetitions do not repeat a separate introduction. Resume, retry and
lock-screen controls retain occurrence identity and accurate verse numbering.
A reusable `001001.mp3` shares its cache entry with Fatihah 1:1 when applicable.

The unverified-opening dialog, Remember setting and consent plumbing are removed;
legacy consent preferences are cleaned on load. Unavailable introductions use
bounded recovery and then continue internally, with a passive notice and honest
offline status. No alternate reciter is substituted. Recordings are not
crossfaded, overlapped or silence-trimmed.

## Selected-ayah translation

The compact translation card opened by the selected ayah's toolbar action applies
bottom SafeArea handling in addition to the modal's top/side protection. Its 8px
floating margin stays above the system navigation area. The reader integration
test opens this actual toolbar action, scrolls through all selected translation
sources, resizes between compact portrait and landscape with 24/48px navigation
insets, measures rendered card/text bounds and checks dismissal.

## Tasbeeh

Settings → Tools → Tasbeeh pushes a separate route, preserving the reader route.
The counter uses a painted charcoal shell, ivory rim, bronze edging, recessed LCD
and vector seven-segment digits with interactive overlaid buttons. The main
ivory button is blank. Themes, reduced motion, semantics and scrolling layouts are
supported. Undo/Reset touch targets remain usable when the device scales down.

Taps anywhere on the screen, including the LCD, shell and surrounding space,
increment once. Undo, Reset, Back and dhikr controls keep their own actions;
scrolls, cancelled gestures and modal interactions do not add counts. The LCD and
main button also expose an accessible count action. The gear opens custom dhikr
management; vibration, sound, targets and completion feedback have been removed.
The management sheet keeps its scrollable actions above the bottom system safe
area, including Android's navigation bar, so Add custom dhikr stays reachable.

Built-in Arabic/transliteration/meaning choices, custom dhikr add/delete, separate
counts and the selected dhikr persist in `tasbeeh_state_v1`. Legacy snapshots are
cleaned of removed options without resetting saved counts or custom dhikr.
Counts use BigInt strings and never roll over at 99999.
Restoration gates counting; a shared store survives navigation while serialized
coalesced writes retain the latest rapid changes.

[Captured preview at 00024](tasbeeh-00024.png). The earlier approved mockup was not
attached to this task, so an exact visual comparison was unavailable. The written
cream-and-charcoal specification was used instead.

## Validation and remaining device checks

Final checks with Flutter 3.38.1 / Dart 3.10.0: `flutter analyze --no-pub` reports
no issues; `flutter test --no-pub --reporter expanded` passes all **358 tests**.
`git diff --check` is clean. The audit builder reproduces 22 canonical sources
from 163 clip records; its Python syntax check also passes.

The regression suite simulates native automatic sequence transitions. It covers
one initial queue setup for adjacent cached ayahs, prefix identity/position,
2,500 transitions with bounded queues, actual Dart player source registration
retention over 1,000 transitions, finite/infinite repetitions, delayed/failed
prefetch, EOF during an in-flight append, healthy-current/future-source failure
isolation, recovery position, stale callbacks, Stop/Pause/navigation/replacement,
background controls, metadata and highlight behavior. Existing statistics,
page-following and Tasbeeh regressions remain included.

Tasbeeh regressions cover screen-wide/rapid/cancelled taps, accessibility actions,
silent counting, legacy migration, serialized saves, restoration, large counts,
Reset confirmation, Back/Settings controls and adaptive phone/tablet layouts.
Dhikr sheets also measure rendered action bounds with gesture/navigation-bar
insets in portrait and landscape, short and long custom lists, and enlarged text.

Production-mapping regressions check all 22 reciters and the exact item/repeat
sequences for Ikhlas → Falaq → Nas, Baqarah → Imran → Nisa, Anfal → Tawbah →
Yunus, and Fatihah → Baqarah. Native automatic source adoption is checked for each
queue in both repeat modes. Actual chosen MP3s are used for source integrity,
automatic downloads and cached/offline introductions. Tests cover cancellation,
replacement, background retry/failure, reserved playback capacity, hash mismatch,
decoder failure, lock-screen commands and duplicate prevention. Synthetic tests
remain only for alternatives/embedded behavior not present in the production map.

Only Linux is available in `flutter devices --machine`. No Android/iOS emulator or
physical phone is attached. Android/iOS builds, audible transition gaps, intrinsic
recitation silence, locked-screen playback, Bluetooth/calls, service survival and
AVQueuePlayer behavior have **not** been measured on hardware. The expanded
[native smoke diagnostic](../tool/audio_repeat_smoke.md) can run generated cached
segments or real short recitations, introductions and repeats. It reports native
index-event timing separately from any actual audio-output measurement. A passing
Dart test or an index-event timestamp cannot establish gapless audible playback.
