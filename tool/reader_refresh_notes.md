# Reader refresh

Implemented: ivory/antique brass/charcoal themes, custom reader icons, floating portrait dock,
attached pull-tabs in portrait and landscape, 100% maximum zoom, separate white/black
reader background preference, playback ayah highlighting, adult daily-return
encouragement, ordered multi-surah listening queues, and Abdullah Basfar.

## Audio investigation

`AudioPlayer.play()` returns a future that lasts until playback ends. Awaiting
that future during preparation or while holding a repeat restart guard can keep
the guard active through another completion. Playback is now started separately
from preparation/restart work, with asynchronous errors reported to the UI.
Repeat restarts and canceled preparation are protected by request generations.
A finite range loads one cycle and seeks back between repetitions. Unrequested
background downloads of the remainder of a surah have been removed. Stop also
cancels preparation; concurrent downloads use distinct temporary filenames.

The existing verse-repeat sequence and offline-first behavior are retained.
Queues download selected recordings before playback, so large queues need time
and storage. The audio sheet explains this and allows cancellation.

Abdullah Basfar source: https://everyayah.com/data/Abdullah_Basfar_192kbps/

## Verification

- Flutter analysis: clean.
- Full suite after the follow-up: 66 tests pass, including finite 1/3/5/10 repeats, infinite recovery,
  cancellation, surah order, preferences, daily activity, geometry and controls.
- Swipe coverage: 16 orientation/zoom combinations, forward and backward page turns,
  vertical landscape scrolling, capped pinch zoom and old preference migration.
- UI previews: `build/reader-previews/`, rendered using the real dock/ayah-action widgets
  with an existing sample Mushaf image. These are component previews, not device
  screenshots. Reproduce with `flutter test --no-pub --dart-define=READER_PREVIEWS=true test/reader_dock_test.dart`.

## Remaining input / device verification

- The two Nigerian reciters need names and compatible verse-level recordings.
  No placeholder reciters or unverified audio URLs were added.
- No Android device was connected. Real playback, lock-screen controls and audio
  through all ten repetitions still require native-device verification.

Android debug build succeeded: build/app/outputs/flutter-apk/app-debug.apk.

## Reader-controls follow-up

Removed the nested horizontal spread scroller that intercepted landscape page
turns. Horizontal swipes now reach PageView; vertical scrolling stays available.
Regression coverage exercises next/previous swipes in both orientations at every
5% zoom step. Zoom is capped at 100%, including previously saved 120% preferences
and portrait pinch magnification. Portrait destinations are icon-only; tooltips
and semantic labels remain available. Both docks use attached, custom-painted
pull-tabs. The selected-ayah toolbar is now 38px high with four accessible icon
actions. Reader background uses the same switch row as other appearance settings.
Green UI accents have been replaced with antique brass and warm charcoal; Mushaf
page artwork and Tajweed colours are unchanged.

## Outer-edge ayah controls and review cadence

Selected-ayah actions now sit below the portrait navigation dock and in a 38px
vertical strip to the right of the landscape dock. Both collapse with navigation.
The audio player leaves space for the expanded dock and selection controls.
Component tests check placement, fit, and all actions in both orientations/themes.

Automatic reviews use a persisted launch count: opens 2, 4, 6, etc. prompt two
minutes after launch on both Android and iOS. A process-wide session guard prevents
repeated scheduling, including background/resume and after dismissal. Manually
opening the review from settings suppresses the automatic prompt for that session.
Regression tests cover six launches, the 119/120-second boundary, repeated
scheduling, and cancellation.
