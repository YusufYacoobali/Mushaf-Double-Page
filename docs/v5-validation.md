# v5 implementation and validation

The implementation starts from main/v4, commit `6d9c429eaa7c939a878a78e9d422732c544179f9`.

## Audio architecture

`QuranAudioController` is the single playback state machine. A bounded logical
cursor holds numbered ayahs, introduction identity, verse repetitions and range
cycles. The native queue contains one recording. `QuranAudioHandler` bridges all
notification, headset, lock-screen and app commands to that same controller.
`just_audio_background` has been removed; `just_audio` remains the engine.

Preparation starts with one recording. The repository prefetches the next three
distinct ayahs and their boundary introductions with at most two concurrent jobs.
Urgent jobs are promoted ahead of queued prefetch jobs. Future download failures
are isolated from current playback. Original numbered cache paths are preserved.
MP3 validation checks ID3 and MPEG frame structure, rejecting HTML, truncated
frames and ID3-only files. Downloads use temporary files and atomic rename.

Recovery preserves the logical item, repetition and playhead. A preparation gets
an initial attempt plus three retries with 1/2/4-second backoff; persistent missing
or unverified sources fail immediately. Decoder failures invalidate only the
current recording. Failed resume positions fall back to restarting that recording.
A separate cap prevents repeated errors after apparently successful native loads
from creating an infinite retry loop. Downloads have connection, receive and
45-second total deadlines; native loads have a 20-second deadline. A 30-second
buffering stall enters recovery. Stop and replacement cancel session requests;
late callbacks cannot start playback. Pause retains the user's intent across
preparation and recovery. EOF reloads reuse source definitions, preserving the v4
iOS AVQueuePlayer workaround.

The modal exposes Retry / Skip ayah (or Continue without Bismillah) / Stop.
The dock remains present during preparation, recovery and failure. Errors persist
after dismissing the modal. Offline downloads are available separately and report
any unverified introductions instead of claiming they were saved.

Introductions do not highlight a numbered ayah or create an ayah listen. Their
listening time still counts. A retry or seek cannot duplicate an already counted
logical occurrence. Covered readers consume follow changes without navigating;
returning does not catch up. Buffering does not reset follow identity.

Android's existing foreground media service, wake-lock permissions and
AudioServiceActivity remain configured. iOS retains UIBackgroundModes=audio.
Interruption begin and headphone disconnect pause the controller. Interruption end
does not automatically resume. These are code/configuration checks, not device
certification.

## Bismillah source audit — 6 November 2026

The following EveryAyah directory listings were inspected. This verifies source
**availability and naming in the listings**, not an auditory review of every
recording. Individual remote files may disappear; those failures use normal
recovery and require an explicit user choice before skipping.

| Reciter | Collection / evidence | Strategy |
| --- | --- | --- |
| Mishary Alafasy | [Alafasy_128kbps](https://everyayah.com/data/Alafasy_128kbps/) | Separate SSS000.mp3 |
| Abdurrahman As-Sudais | [Abdurrahmaan_As-Sudais_192kbps](https://everyayah.com/data/Abdurrahmaan_As-Sudais_192kbps/) | Separate SSS000.mp3 |
| Abdul Basit Murattal | [Abdul_Basit_Murattal_192kbps](https://everyayah.com/data/Abdul_Basit_Murattal_192kbps/) | Separate SSS000.mp3 |
| Abdul Basit Mujawwad | [Abdul_Basit_Mujawwad_128kbps](https://everyayah.com/data/Abdul_Basit_Mujawwad_128kbps/) | Separate SSS000.mp3 |
| Al-Husary | [Husary_128kbps](https://everyayah.com/data/Husary_128kbps/) | Unverified: no listed 002000/112000; do not infer embedded audio |
| Abu Bakr Ash-Shaatree | [Abu_Bakr_Ash-Shaatree_128kbps](https://everyayah.com/data/Abu_Bakr_Ash-Shaatree_128kbps/) | Separate SSS000.mp3 |
| Ahmed Al-Ajamy | [ahmed_ibn_ali_al_ajamy_128kbps](https://everyayah.com/data/ahmed_ibn_ali_al_ajamy_128kbps/) | Separate SSS000.mp3 |
| Maher Al Muaiqly | [MaherAlMuaiqly128kbps](https://everyayah.com/data/MaherAlMuaiqly128kbps/) | Separate SSS000.mp3 |
| Al-Minshawy Murattal | [Minshawy_Murattal_128kbps](https://everyayah.com/data/Minshawy_Murattal_128kbps/) | Separate SSS000.mp3 |
| Al-Minshawy Mujawwad | [Minshawy_Mujawwad_192kbps](https://everyayah.com/data/Minshawy_Mujawwad_192kbps/) | Separate SSS000.mp3 |
| Hani Rifai | [Hani_Rifai_192kbps](https://everyayah.com/data/Hani_Rifai_192kbps/) | Unverified: no listed 002000/112000; do not infer embedded audio |
| Ali Al-Hudhaify | [Hudhaify_128kbps](https://everyayah.com/data/Hudhaify_128kbps/) | Separate SSS000.mp3 |
| Muhammad Ayyoub | [Muhammad_Ayyoub_128kbps](https://everyayah.com/data/Muhammad_Ayyoub_128kbps/) | Separate SSS000.mp3 |
| Nasser Al Qatami | [Nasser_Alqatami_128kbps](https://everyayah.com/data/Nasser_Alqatami_128kbps/) | Separate SSS000.mp3 |
| Yasser Ad-Dussary | [Yasser_Ad-Dussary_128kbps](https://everyayah.com/data/Yasser_Ad-Dussary_128kbps/) | Separate SSS000.mp3 |
| Saud Ash-Shuraym | [Saood_ash-Shuraym_128kbps](https://everyayah.com/data/Saood_ash-Shuraym_128kbps/) | Separate SSS000.mp3 |
| Abdullah Basfar | [Abdullah_Basfar_192kbps](https://everyayah.com/data/Abdullah_Basfar_192kbps/) | Mixed collection: 112000/113000/114000 enabled; other surahs remain unverified |
| Saad Al-Ghamdi | [Ghamadi_40kbps](https://everyayah.com/data/Ghamadi_40kbps/) | Named standalone bismillah.mp3; 002000 is absent |
| Fares Abbad | [Fares_Abbad_64kbps](https://everyayah.com/data/Fares_Abbad_64kbps/) | Separate SSS000.mp3 |
| Abdullah Al-Juhany | [Abdullaah_3awwaad_Al-Juhaynee_128kbps](https://everyayah.com/data/Abdullaah_3awwaad_Al-Juhaynee_128kbps/) | Separate SSS000.mp3 |
| Ali Jaber | [Ali_Jaber_64kbps](https://everyayah.com/data/Ali_Jaber_64kbps/) | Separate SSS000.mp3 |
| Salah Bukhatir | [Salaah_AbdulRahman_Bukhatir_128kbps](https://everyayah.com/data/Salaah_AbdulRahman_Bukhatir_128kbps/) | Separate SSS000.mp3 |

The app does not guess 000000.mp3, reuse another reciter, or assume a missing file
means the opening ayah includes Bismillah. Unverified cases present an explanation
with Retry, Continue without Bismillah and Stop. **Al-Husary, Hani Rifai and the
remaining Basfar openings need an auditory audit before their policies can be
expanded.** The enabled SSS000 introductions and adjacent opening ayahs also need
listening checks to rule out upstream segmentation/content errors.

Al-Fatihah and At-Tawbah never get a separate introduction. Starting after ayah 1
omits it. A completed introduction is not replayed on an ayah retry or verse repeat;
a range cycle starting at ayah 1 includes it again.

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

Final checks with Flutter 3.38.1 / Dart 3.10.0: `flutter analyze` reports no
issues; `flutter test` passes all **195 tests**. `git diff --check` is clean.

Automated tests cover the real repository with controlled Dio transport and real
filesystem/MP3 fixtures, plus delayed native-source loads, stream errors and sticky
EOF. They cover recovery limits, stale sessions, interruption/pause intent,
background command routing, range/verse repeats, surah boundaries, introduction
identity/offline cache, modal recovery controls, statistics and page following.
Tasbeeh tests cover rapid/cancelled taps, serialized saves, restoration, targets,
large counts, Reset confirmation, Settings navigation and small/large phones,
landscape and tablet layouts in both themes at increased text scale.

`flutter devices --machine` found only Linux. No Android/iOS emulator or physical
phone is attached. Native lock-screen, Bluetooth, calls, background service
survival, AVQueuePlayer repeats and audible reciter content **have not been
validated on hardware**. Use the updated `tool/audio_repeat_smoke.dart` harness
and `tool/audio_repeat_smoke.md`, then test real recitations on both platforms.
The smoke harness uses a generated tone and does not certify Bismillah content.
