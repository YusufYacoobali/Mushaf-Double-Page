# v5 implementation and validation

This follow-up starts from `de190cf` on the existing `v5` branch. It changes audio
and Bismillah handling only. Tasbeeh implementation, settings and its captured
preview are unchanged. Nothing is merged into `main`.

## Continuous playback queue

`QuranAudioController` remains the single playback controller. It starts when the
first required recording is ready, then incrementally appends prepared sources in
logical order. The target is the current occurrence plus three future occurrences,
with at most one consumed occurrence retained. The hard native limit is six,
including introductions. Download concurrency remains two, and a newly needed
prefetch job is promoted instead of starting a duplicate request.

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
intent survives replenishment. Stop, Next and replacement invalidate pending
session work, downloads, appends and stale callbacks.

A future decoder error is resolved through its reported source index and the
actual native sequence tag. Its suffix is deferred without invalidating or
interrupting a healthy current recording. Repair occurs at its boundary without
consuming a repeat. If the native engine itself becomes idle, the current source
can be reloaded at its saved position without deleting a healthy cache entry.
Preparation has an initial attempt plus up to three exponential-backoff retries;
persistent missing files fail immediately. A separate decoder-restart cap prevents
an endless native failure loop. Retry / Skip ayah or introduction / Stop remain
explicit choices; numbered ayahs are never silently skipped.

MP3 validation, atomic temporary-file publication, connection/receive/total
request deadlines, native load deadlines and buffering-stall recovery remain.
Hash-bound opening policies also validate cached/downloaded introduction and
first-ayah bytes, including offline selection downloads. Original numbered cache
paths remain compatible.

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

## Bismillah content audit — 6 November 2026

The previous directory-name assumptions have been replaced with per-surah
policies: `notRequired`, `embeddedInOpeningAyah`, `separateVerifiedRecording`, or
`unverified`. Each enabled destination and separate source is bound to the SHA-256
of the content examined. Descriptors carry the source URL, physical/cache identity,
evidence and independently checked same-collection alternatives where available.

**Actual audio review performed:** 163 MP3 clips spanning all 22 configured
reciters were decoded with ffmpeg and transcribed in Arabic using sherpa-onnx
multilingual Whisper tiny and small int8, with base-model corroboration for a
subset. Samples cover available `001000/001001`, `002000/002001`,
`112000/112001`, `114000/114001`, plus the named `bismillah.mp3` recordings found
for Al-Husary, Hani Rifai and Al-Ghamdi. This is automatic content review, **not
human listening or independent voice/style identification**. ASR can omit or
hallucinate words, particularly in recitation and muqattaat.

Direct EveryAyah requests were blocked by the environment's network policy. Actual
bytes were obtained from the public [maqra mirror](https://github.com/Abdalla-Eldoumani/maqra)
at revision `cf6f004bfb5fa24017db479d39676a4a908f518a`. Its manifests identify the
EveryAyah collection, reciter/style, file SHA-256 and upstream-MD5 verification
state. Downloaded bytes were checked against those hashes. The app still requests
the original EveryAyah URL and rejects changed bytes for enabled policies.

[The committed evidence](bismillah-content-audit.json) contains clip URLs,
durations, actual model transcripts, hashes, manifest matches, provenance and the
complete enabled policy data. Model release URLs are recorded there. The
[policy builder](../tool/build_bismillah_audit.py) requires a clean normalized
small-model Bismillah phrase, rejects recognized isti‘adhah in corroborating
output, and requires the destination opening transcript to match its ayah alone
before adding anything. Missing or ambiguous evidence does not enable a policy.

Findings that changed the old assumptions:

- Al-Husary and Hani Rifai have named Bismillah recordings. Their named clips
  transcribe as exactly the intended phrase in both tiny and small models;
  separately examined `001001.mp3` files provide alternatives.
- Abdullah Basfar's sampled `001001.mp3` transcribes as Bismillah alone and can be
  reused for the three examined destinations below. Its other destinations are
  not inferred from that result.
- Abdul Basit Murattal's sampled `SSS000` clips include isti‘adhah as well as
  Bismillah; they are not enabled as clean introductions. A clean same-collection
  `001001.mp3` is used only with checked destinations.
- Ash-Shaatree's sampled `SSS000` files transcribe as isti‘adhah without Bismillah.
  Plausible filenames are therefore insufficient. That collection remains
  unresolved in the production policy.

### Enabled coverage and unresolved openings

**32 destination openings across 18 reciters** currently meet the automated audit
criteria. All are separate-introduction policies; embedded behavior is implemented
and tested with explicit synthetic fixtures, but no actual sampled destination
provided conclusive embedded evidence. The table lists all enabled surahs.
Every other surah from 2–114 except 9 remains `unverified` for that reciter,
including unreviewed destinations and ambiguous sampled clips. This is partial
coverage, not a completed corpus-wide listening audit: **2,432 of 2,464 applicable
reciter/surah openings still need verification**.

| Reciter | Enabled surahs |
| --- | --- |
| Mishary Alafasy | 112, 114 |
| Abdurrahman As-Sudais | 112, 114 |
| Abdul Basit Murattal | 112, 114 |
| Abdul Basit Mujawwad | 114 |
| Al-Husary | 112, 114 |
| Abu Bakr Ash-Shaatree | None |
| Ahmed Al-Ajamy | 112, 114 |
| Maher Al Muaiqly | 112 |
| Al-Minshawy Murattal | 112, 114 |
| Al-Minshawy Mujawwad | None |
| Hani Rifai | 112, 114 |
| Ali Al-Hudhaify | 112, 114 |
| Muhammad Ayyoub | 112, 114 |
| Nasser Al Qatami | 114 |
| Yasser Ad-Dussary | 112, 114 |
| Saud Ash-Shuraym | 2, 114 |
| Abdullah Basfar | 2, 112, 114 |
| Saad Al-Ghamdi | 112 |
| Fares Abbad | 2, 114 |
| Abdullah Al-Juhany | None |
| Ali Jaber | None |
| Salah Bukhatir | 112 |

Before a selection starts, unresolved openings produce one Continue/Cancel choice,
with optional Remember for this reciter. The dialog explicitly says original
recordings do not guarantee Bismillah. Consent applies to the selection and its
repeats; verified policies elsewhere remain enabled. Unverified introductions
never enter network retry loops. Offline download reports unresolved coverage
instead of claiming all introductions are available.

Verified introduction failures try configured verified alternatives, then bounded
recovery. Continue without the additional introduction suppresses that physical
introduction for the session and still plays ayah 1. No different reciter is
substituted. Al-Fatihah and At-Tawbah never get an added introduction. Starting
after ayah 1 adds none, and resuming/retrying a numbered ayah never replays its
finished separate introduction. Recordings are not crossfaded, overlapped or
silence-trimmed.

## Tasbeeh

Settings → Tools → Tasbeeh pushes a separate route, preserving the reader route.
The counter uses a painted charcoal shell, ivory rim, bronze edging, recessed LCD
and vector seven-segment digits with interactive overlaid buttons. The main
ivory button is blank. Themes, reduced motion, semantics and scrolling layouts are
supported. Undo/Reset touch targets remain usable when the device scales down.

Built-in Arabic/transliteration/meaning choices, custom dhikr add/delete, separate
counts, per-dhikr targets, vibration/sound preferences and target feedback persist
in `tasbeeh_state_v1`. Counts use BigInt strings and never roll over at 99999.
Restoration gates counting; a shared store survives navigation while serialized
coalesced writes retain the latest rapid changes. Targets give feedback at each
multiple and never reset the count.

[Captured preview at 00024](tasbeeh-00024.png). The earlier approved mockup was not
attached to this task, so an exact visual comparison was unavailable. The written
cream-and-charcoal specification was used instead.

## Validation and remaining device checks

Final checks with Flutter 3.38.1 / Dart 3.10.0: `flutter analyze --no-pub` reports
no issues; `flutter test --no-pub --reporter expanded` passes all **208 tests**.
`git diff --check` is clean. The audit builder regenerates 163 clip records and
32 enabled destination policies; its Python syntax check also passes.

The regression suite simulates native automatic sequence transitions. It covers
one initial queue setup for adjacent cached ayahs, prefix identity/position,
2,500 transitions with bounded queues, actual Dart player source registration
retention over 1,000 transitions, finite/infinite repetitions, delayed/failed
prefetch, EOF during an in-flight append, healthy-current/future-source failure
isolation, recovery position, stale callbacks, Stop/Pause/navigation/replacement,
background controls, metadata and highlight behavior. Existing statistics,
page-following and Tasbeeh regressions remain included.

Bismillah tests distinguish synthetic behavior fixtures from actual audit
evidence. They cover separate/embedded/unverified mixtures, per-surah policy,
playlist/repeat consent, persistence per reciter, verified alternatives, offline
cache reuse, mismatched opening hashes and introduction identity. An integrity
test checks that all production descriptors match the committed same-collection
clip evidence; it does not certify ASR accuracy.

Only Linux is available in `flutter devices --machine`. No Android/iOS emulator or
physical phone is attached. Android/iOS builds, audible transition gaps, intrinsic
recitation silence, locked-screen playback, Bluetooth/calls, service survival and
AVQueuePlayer behavior have **not** been measured on hardware. The expanded
[native smoke diagnostic](../tool/audio_repeat_smoke.md) can run generated cached
segments or real short recitations, introductions and repeats. It reports native
index-event timing separately from any actual audio-output measurement. A passing
Dart test or an index-event timestamp cannot establish gapless audible playback.
