# v9 maintenance work

## Completed extractions

| Area | Ownership after the refactor | Regression coverage |
| --- | --- | --- |
| Startup and reader | `main.dart` initializes the services and exports the existing public entrypoints. The app owns theme and review-prompt configuration. The reader owns lifecycle, page commits and its existing paging and audio followers. Its annotations and overlays share that reader state. | [Reader screen](../lib/reader/reader_screen.dart) · [Page turns](../test/reader_turn_navigation_test.dart) · [Audio following](../test/audio_page_follower_test.dart) |
| Translation | The loader assembles typed Surah headers and ayahs from the selected sources. Page mode uses the merged printed-page segments. Whole-Surah mode uses the first translation's numbered verses. The modal owns focus, scrolling and pagination. Settings, summary and ayah widgets render their own surfaces. | [Content assembly](../lib/components/translation/translation_content.dart) · [Both loading modes](../test/translation_content_test.dart) · [Translation safe areas](../test/ayah_translation_safe_area_test.dart) |
| Audio | The controller owns the playback cursor, bounded queue, backend handoff and recovery. Offline saves own their cancellation token, retry schedule and progress while sharing the recording repository with playback. Listening progress samples the presented occurrence using the existing tracker. | [Offline saving](../lib/logic/offline_audio_downloads.dart) · [Download regressions](../test/automatic_audio_download_test.dart) · [Continuous backend](../test/continuous_pcm_backend_test.dart) · [Journey tracking](../test/journey_test.dart) |
| Storage | Reader preferences and bookmark serialization stay in `StorageManager`. Its installation methods delegate to the installer, which owns Firebase downloads, staging, validation and rollback. Existing callers keep their signatures. | [Installer](../lib/logic/mushaf_installer.dart) · [Installation compatibility](../test/mushaf_installation_test.dart) · [Reader preferences](../test/reader_preferences_test.dart) |

The pre-refactor Flutter suite passed 611 tests, with two conditional skips. The four phase-specific runs passed 113 reader tests, 25 translation tests, 145 audio tests and 35 storage tests. The populated translation view, settings sheet and Surah summary matched the reference phone renders pixel for pixel.

## Final validation

The application revision tested was `eb4afbe`, compared with `8d29f3e` before extraction.

- Flutter analysis passed. The full suite passed 614 tests. Both conditional tests also passed separately. One exercised the release guard with `dart.vm.product=true`. The other validated a sample-exact PCM fixture generated from eleven checksummed Yasser recordings.
- All 45 before-and-after Flutter renders matched pixel for pixel. These included the phone dock, navigator, reader selection, translation surfaces, and iPad mini portrait and landscape at 100% zoom. The iPad comparison opened page 6, rotated the running reader and verified the facing pages 6 and 7.
- An Android emulator played cached Al-Juhany 112:2–3 twice through continuous PCM, in the order 2, 3, 2, 3, with one queue load. Both ayahs and listening time persisted. Recovery, highlighting and navigation passed their regression tests. The emulator reported output underruns, so this run verifies ordering and continuity in the engine. Audible continuity on physical speakers was not measured.
- The Android debug build and both Samsung foldable profiles passed, including the screenshot comparison. [Android build and visual results](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46024159684)
- The arm64 iOS simulator build passed. The Duo passed all four postures at minimum and maximum zoom. The iPad mini passed portrait and landscape at 100%, and the workflow assembled the twelve verified captures. Two earlier iPad attempts stopped at page installation and portrait screenshot verification respectively. The successful run used the same application build and screenshot checks. [iOS build and visual results](https://github.com/YusufYacoobali/Mushaf-Double-Page/actions/runs/46024159688)

## Remaining concentrations

- The audio controller is the largest Dart file at 1,477 lines. Queue installation, cancellation and recovery all validate the same session and revision before accepting asynchronous results. Keeping these operations together makes their ordering reviewable. Revisit extraction if a backend gains independent policy.
- The audio modal is 937 lines. Its selection and download sections are candidates for presentation-only widgets when that form next changes. Its draft playback plan belongs to the modal.
- The translation modal is 878 lines. A separate Surah picker or header widget could help when those controls change. Pagination, focus and the scroll controller have a shared lifecycle.
- The reader screen is 590 lines. It owns the platform subscriptions and the page commit that coordinates persistence, progress and audio following. Further splitting those operations would add coordination across files.

## Visual verification on v9

Use Flutter 3.38.1. Run the ordinary-phone dock renders and responsive surface captures from the repository root.

```sh
flutter test --no-pub --dart-define=READER_PREVIEWS=true test/reader_dock_test.dart
RESPONSIVE_SCREENSHOTS=/tmp/reader-surfaces flutter test --no-pub tool/responsive_visual_smoke_test.dart
```

For native verification, append the reason for a new run to the corresponding request file and push it to `v9`. The [Duo and iPad mini workflow](../.github/workflows/complete-visual-20261118.yml) watches [its request file](../.github/complete-visual-20261118.request). It builds the iOS simulator app, checks Duo folded, open and book postures at the zoom endpoints, and captures iPad mini portrait and landscape at 100%. The [Android foldable workflow](../.github/workflows/samsung-foldable-visual-check.yml) watches [its request file](../.github/samsung-foldable-visual.request) and supports manual dispatch. It verifies the passport and regular Samsung-dimension emulator profiles.

Inspect the workflow results for the requested revision, including geometry and original screenshot artifacts. Earlier layouts and device measurements are documented in the [iPad and Duo regression report](ipad-duo-layout-regression.md) and [v9 validation report](v9-validation.md).
