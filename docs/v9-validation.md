# v9 validation

For the subsequent Samsung speaker investigation, see the [Android waveform comparison and scoped polarity correction](v9-samsung-audio.md).

## Al-Juhany’s premature restart

The cached originals for 2:253, 2:255 and 2:282 each played through one occurrence to EOF in the production Android PCM output probe. Scheduled, decoded and presented frame counts agreed at completion. The probe bypasses Flutter and network acquisition. It did not reproduce a spontaneous native error. The trigger on the reporting device remains unknown.

| Al-Juhany recording | FFmpeg frames at 44.1 kHz | Android frames at completion | AudioTrack underruns |
| --- | ---: | ---: | ---: |
| 2:253 | 2,028,719 | 2,028,672 | 1 |
| 2:255 | 1,812,143 | 1,812,096 | 394 |
| 2:282 | 5,516,975 | 5,516,928 | 210 |

These are API 29 software-emulator results. The underrun counts describe that runtime. There was one timeline row, one generation and no native error in each selection. Full independent durations for 2:255 and 2:282 were 41.092 and 125.101 seconds.

Two controller behaviours were reproducible independently of the recording.

- A pending 30-second buffering watchdog used to recover from a stale UI event even when the native worker had advanced. A regression holds the UI at frame 200 and advances the worker to 26,000. Playback now continues. A further interval with genuinely unchanged clocks still enters recovery.
- A mid-ayah failure used to release the native output and install the same occurrence at zero. The regression failed on the original controller. It injects a route error into a repeat-one selection at frame 1,800,001 of the 2:282 reference timeline (40.816 s). The repaired controller retries the same prepared source and decoder once at that exact frame and stops at true EOF. Tests also cover stale generations, future-recording failure, a second failure, pause, seek, repeats, highlighting and page turns. The legacy handoff starts the current occurrence from its beginning when a cross-decoder seek cannot be verified.

Core Audio’s stereo 44.1 kHz fast path used to poll the estimated compressed-file length. If a read returned zero frames below that estimate, the loop could continue without emitting PCM or closing the occurrence. Both decode paths now use the reader’s EOF. Al-Juhany’s Info frame counts exceed FFprobe’s audio packet counts by one (1,575 vs 1,574 for 2:255, 4,791 vs 4,790 for 2:282). The metadata discrepancy alone does not establish Core Audio’s behaviour on these files or explain a restart halfway through an ayah.

## Ayah joins

FFmpeg 7.1.5 decoded **172 original recordings and 104 selected joins across all 22 configured reciters**, including 22 introductions. Each reciter contributed 112:1–4, 2:255 and 2:282. Al-Juhany also contributed short contiguous passages from 55 and 113 and adjacent verses from 2. The audit records compressed and decoded SHA-256, format, sample counts, encoder declarations, decoder skip/discard and edge levels per file. Formats observed were 44.1 kHz stereo and 22.05 kHz mono/stereo. Per-reciter measurements and unmeasured output fields are in the [audio audit](v9-audio-audit.json).

Direct EveryAyah access returned HTTP 403. Every file matched the pinned mirror’s size and SHA-256. Its manifests report 160 upstream MD5 matches, eight missing upstream MD5s, two extra introduction files, and two introduction MD5 mismatches (Muaiqly and Shuraym 001001). All sampled Al-Juhany files had upstream matches. Original MP3s remain outside this change. [Pinned mirror and manifests](https://github.com/Abdalla-Eldoumani/maqra/tree/cf6f004bfb5fa24017db479d39676a4a908f518a)

Al-Juhany’s LAME3.98r headers declared 576 samples of delay and 576 of padding. FFmpeg skipped 1,105 samples and discarded zero at the tail of the selected Al-Ikhlas files. The independent float PCM has **zero exact silence and zero edge quiet at −60 dBFS** at both 112:1→2 and 112:3→4. At 112:2→3 it has 1.088 ms of digital zero and 5.669 ms below −60 dBFS. The thresholds describe the source.

| Recording | Independent S16 frames | Android S16 frames | Leading zero frames, reference / Android |
| --- | ---: | ---: | ---: |
| 112:1 | 106,031 | 105,984 | 702 / 1,258 |
| 112:2 | 87,599 | 87,552 | 0 / 138 |
| 112:3 | 115,247 | 115,200 | 123 / 123 |
| 112:4 | 155,567 | 155,520 | 0 / 145 |

This is a **decoder-output difference before scheduling**. The Android decoder emits 3.13 ms and 3.29 ms of zeros where the S16 reference begins with signal on 112:2 and 112:4. Interior landmarks align within each file. Across all three joins they arrive 47 frames (1.066 ms) earlier per boundary in the concatenated Android decode, with correlations above 0.99999999. The reference’s extra 47 tail frames contain nonzero samples in all four files. Interpreting those samples as disposable would require independent evidence.

The Android writer submits adjoining sample arrays to one streaming AudioTrack and retries partial writes at the next unwritten sample. It inserts zero spacer frames in that code path. There is no speaker or audio-loopback measurement of the scheduler, route or acoustic gap in this run. The quantified Android difference comes from native decode; the contribution of each platform codec to the audible impression still requires a device capture. No sample-processing fix, silence trimming, fade, crossfade or emulator-specific buffer tuning was applied.

### Reproducing the bounded checks

Use the mirror revision above. The audit extracts selected MP3s from per-surah archives and reuses a populated cache on subsequent runs.

```sh
python3 tool/audit_reciter_joins.py /path/to/maqra /tmp/v9-audio /tmp/v9-audit.json
python3 tool/everyayah_transition_probe.py original-reference \
  --directory /tmp/juhany-reference \
  --originals /tmp/v9-audio/abdullah_juhany/11200{1,2,3,4}.mp3
```

The Android probe in `tool/native_tests/ReciterJoinProbe.kt` compiles alongside the plugin’s production Kotlin sources with android.jar and Flutter’s embedding JAR, then runs as dex through adb. Each selection-file line lists absolute cached MP3 paths separated by spaces. Use one line for Al-Ikhlas and one for a single long ayah. The optional `decode` argument writes little-endian stereo S16 for sample comparison. Omitting it exercises AudioTrack and emits a timeline. For a real output capture, run the existing probe’s `measure` action against a 44.1 kHz S16 capture with the original reference directory and compare with playback of its reference WAV over the same route.

For iOS XCTest, stage just the verified 002255.mp3 and 002282.mp3 in the test host’s Documents/v9-juhany. `testJuhanyLongRecordingsReachEOF` verifies the hashes and compares real AVAudioFile output counts to the independent reference. It explicitly skips when the fixtures are absent. iOS execution, acoustic capture and physical-device acceptance remain pending. On the affected device the most discriminating check is a direct repeat-one 2:282 play, first cached and then during normal acquisition, capturing the first native reason and frame counters before recovery. Record OS, route, foreground/background state and any interrupt alongside that event.

## Juz divisions and page navigation

The main Juz row jumps to quarter 1. Its chevron reveals quarters 2–4. Navigation goes through the edition’s local verse-to-page index, including the existing three cover pages, and supplies the boundary surah. All 120 destinations in each of Madani, Indo-Pak and Indo-Pak Tajweed are tested. The two Indo-Pak editions share the reader’s 13-line page index.

- **Madani.** The table uses alternate starts from Quran Android’s 240 rub divisions, yielding 120 starts. All 120 destinations agree with the page containing the boundary verse in DigitalKhatt’s 604-page old-Madinah transcription. Of these boundaries, 89 also have an explicit inline rosette there. Madani Juz 8 now opens printed page 142 (logical 145), containing 6:111. Its former logical destination was 143. The source projects use GPLv3 and MIT respectively. Only numeric references were transcribed. [Quran Android divisions](https://github.com/quran/quran_android/blob/280bf446188ab6fbff4ed6fb5ba4937d822e045d/pages/data/madani/src/main/kotlin/com/quran/labs/androidquran/pages/data/madani/MadaniDataSource.kt) · [DigitalKhatt old-Madinah pages](https://github.com/DigitalKhatt/digitalkhatt-js/blob/d1a747344bf9be60b8152ad6c7bd56d1092729b3/apps/site-angular/src/app/services/quran_text_old_madinah.ts)
- **Indo-Pak.** The reference was the 847-page 13-line print, SHA-256 `0e6e9e1ba3adb47062cadcc2e17f5612a44a7c2df367bd1ff74139ed9c3e0ab3`. All 90 internal margin signs were located and cross-referenced with the app’s verse/page text. For example, Juz 1 quarter 2 starts at 2:47 here and 2:44 in Madani. The Juz 7 quarter 4 sign is within 6:73. Two margin signs point to a line with multiple verse endings (38:53–54 and 44:22–24). The exact word at the division is ambiguous in that print. Every candidate lands on the same selected page in both Indo-Pak editions, enforced by a test. The mirror lists no standalone reproduction licence for the print. Only the numerical references are bundled. The app’s remote page-image service was unavailable for a separate image-by-image comparison. [Reference 13-line print](https://github.com/bilalix/qurans-for-ereaders/blob/4bcafc0b01bb1c76a700c3bc5985ca859cda970b/kindle_kobo_oxyx_etc/pdf/indopak/quran_13_lines.pdf)

## Folded dock and visual checks

On a closed iPhone Duo, the reader places the vertical dock in the clear portion of the right-hand strip reported by UIKit. It excludes active camera, division and status-bar frames and keeps the lower gesture inset clear. Secondary ayah and audio actions scroll in the same column. Unfolding restores the ordinary controls and the reader’s saved arrow-only preference. On Android, an inward-folding Pixel Fold-family or Samsung SM-F9-family model must report a closed hinge (0°) on the activity’s default display. This requires Android 11 or newer and a public hinge-angle sensor. Other phones and devices with unavailable signals follow their existing policy. Detection is scoped to the foreground activity. The Android hint only selects dock placement.

All 24 ordinary-phone dock renders matched the starting commit (190bd08) pixel for pixel at 320 × 568, 390 × 844 and 844 × 390, including light/dark, expanded/collapsed and selection/playback states. Local Flutter renders were inspected for the expanded Juz panel, a 360 × 800 cover with expanded audio and collapsed controls, ordinary portrait and landscape. The geometry tests cover folded portrait/landscape, asymmetric insets, hinge-safe book layouts, iPad precedence, multiple zoom levels, hit testing, animated dock expansion and page bounds. The original folded implementation placed the pull tab inside the safe reading area. [Selected Flutter renders](v9-reader-checks.jpg)

In the iOS 27.1 Duo simulator, the 466 × 678 point folded window reported an 84-point right strip. The camera and status area occupied its upper portion. The page kept its 382-point width at both 70% and 100% zoom. The dock was centered at x=424 and was still visible after eleven seconds idle. These dimensions are measurements from the capture. Placement uses the current window and reserved-region frames. [UIKit reserved regions](https://developer.apple.com/documentation/uikit/uiview/reservedregion)

The four-device run compared 32 native captures with the previous v9 originals. All page frames matched. Both iPad mini images matched to the precision reported by the comparison, as did 19 of the 20 Samsung images. The remaining Samsung image matched at 99.999%. Three unfolded Duo captures caught the auto-hiding dock in a different state than the reference. [Duo and iPad captures](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46039509707) · [Samsung captures](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46039509710)

### Folded Duo touch delivery and unfolding

The failed native run captured a clear reader before its unconditional permission tap. The tap selected 2:10. The next screenshot, the folded 100% zoom screenshot and the unfolded landscape screenshot all show the system’s “Quran Dual Page” notification prompt. Flutter continued publishing page and button geometry beneath the prompt. The folded image’s near-white fraction fell from 25.18% before the setup tap to below 0.01% at the failed endpoint. [Original failed run](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46042757129) · [Inspection of original PNGs](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46052738494)

The Duo harness waits for the OS notification authorization decision and two unobstructed screenshots. It targets the active display in interface points and records the requested point, UIKit window hit test, native touch recipient, Flutter pointer events and zoom callback. It also reads the resulting reader state. These probes are installed only in the disposable simulator build. Native playback checks use the nine original Alafasy recordings for 2:5–13, each matched to the pinned mirror SHA-256 and upstream MD5. [Apple’s reserved-region guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)

Selecting an ayah or starting playback while the cover dock is pinned now updates the visibility used on unfolding. A selection that held the dock open on unfolding restarts the normal idle timer when cleared. Regression tests start from hidden controls, cover both arrow-only settings, and check the selected verse, page, 95% zoom, playback session, position and native queue load count.

On the active 466 × 678 point cover, UIKit reported `FlutterView` for the printed ayah and the navigation strip. Each of four native zoom taps produced one callback and the expected rendered 100% → 95% → 100% sequence, both with 2:9 selected and with no selection. The idle capture retained the expanded dock and its bounds after 11 seconds. All five dock destinations, page and ayah bookmarks, translation, strip scrolling and audio transport passed. Both `duoctl` and XCUITest delivered touches. In the final run, unfolding and refolding preserved page 6, 100% zoom, selection 2:10 and the same audio session paused at 2,826 ms. Stop and clear-selection then restored the idle reader. The run recorded 39 delivered gestures and 41 resulting state checks. [Final Duo originals and native traces](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46064466719/artifacts/15230744599)

All 32 device page geometries matched the previous successful v9 verification. The seven unfolded or half-open Duo comparisons, both iPad mini comparisons and all 20 Samsung comparisons showed 100.000% identical pixels at the reported precision. The three folded Duo captures had matching page frames and showed the new right-side dock. Their identical-pixel percentages were 90.157% at 70% zoom, 81.918% at 100% zoom and 90.170% after inactivity. [iOS comparison](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46064466719/job/140736572182) · [Original iPad captures](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46056568022/artifacts/15227920554)

Flutter analysis passed. The full suite passed 621 tests with two conditional skips. Both conditional tests passed separately with release mode and the generated Yasser recording artifact respectively. The seven folded-Duo widget tests passed, including selection and playback started with the dock previously hidden. Restoring the old guards made both default-preference transition tests fail. The 32 dock renders and four responsive renders matched their pre-change images byte for byte. All 36 Python verification tests passed.

[Original Galaxy foldable captures](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46052490922/artifacts/15225578489) · [Original passport-style foldable captures](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46052490922/artifacts/15225114688)

## Earlier v9 regression results

- Flutter static analysis passed. The full Flutter suite passed 603 tests with two existing conditional skips (release-only test and optional generated Yasser artifact). The focused navigation, verse-index and continuous-PCM suite passed 39 tests.
- Android debug APK built. All six Android PCM JVM unit tests passed. The native production probes above ran on Android 10/API 29 x86_64. The full connected Android instrumentation suite and iOS XCTest suite were not run.
- Eight Python audio-tool tests and 32 visual-verifier tests passed. The 360 × 800 dock render/control test passed all four light/dark and audio combinations. Git whitespace checks passed.
