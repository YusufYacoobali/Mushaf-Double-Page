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
- Verification after the follow-up: 104 tests pass, including finite 1/3/5/10 repeats, infinite recovery,
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

## Motion and Quran Journey

Shared motion uses a 380ms arrival / 260ms departure, with reduced-motion support.
Reader docks glide from the edge, arrows interpolate, icons stagger in, and nav,
zoom and ayah buttons have press feedback. Sheets/dialogs use shared timing;
settings, translations and Journey use refined Material page transitions while
iOS retains its interactive Cupertino navigation. Audio/welcome/ayah overlays
retain outgoing content for a fade without retaining its hit targets.

"Your Quran Journey" replaces "Your daily practice". It shows current/best streak,
pages opened, ayahs listened to, translations read, reading/listening time, active
days, surahs explored through listening, and distinct ayahs heard. Totals are
local, cumulative and serialized in SharedPreferences. Existing streaks are
preserved; new statistics start with this update and show a tracking start date.
Current streak expires after a missed calendar day; best streak is retained.

Page visits count newly displayed Quran pages (including both pages of a spread),
not rebuilds. Reader time counts foreground time on the uncovered reader route,
flushing every 15 seconds and when leaving/backgrounding; an abrupt process kill
can lose the unflushed interval. Translations count once per verse per visit after
two seconds in the viewport. Listening counts advancing position, rejects large
seek jumps, and qualifies an ayah after 90% of its duration; repeats count again.
Listening time is saved in 15-second batches and on pause/stop.

Regression coverage includes rapid dock reversal, outgoing-overlay hit testing,
press cancellation, route results, reduced motion, concurrent stats updates,
streak migration, repeat listening, hidden translation text and covered reader
time. Journey previews in `build/reader-previews/journey-*.png` use sample test
data, in both themes at 320px, 390px and landscape widths. Native-device audio
telemetry and animation performance still need on-device verification.

## Integrated audio dock and total app time

Playback controls now live inside the same dock panel: a compact upper row in
portrait and a parallel vertical section in landscape. The ayah selection bar
remains below / to the right. Playback and navigation share the attached pull-tab,
theme, press feedback, and animated visibility. Previous, play/pause, next and
audio settings retain their existing callbacks. Audio state no longer creates a
separate floating mini-player. Expanded audio also reserves space beside the
landscape welcome card. Preview files with `-audio.png` show the combined layout.

The Journey screen replaces distinct ayahs with total app time. A single root
tracker uses a monotonic clock across every route, excludes inactive/background
time, and flushes every 15 seconds, on lifecycle transitions, disposal and before
loading Journey stats. The new metric starts at zero; existing statistics are
preserved. Abrupt termination may lose the most recent unflushed interval.
Tests exercise repeated initialization, fractional seconds, all inactive states,
independent listening/reading totals, controls in both dock layouts, and audio
starting/stopping during dock animations.

## Remembered highlight and combined ayah/audio controls

Selected ayahs are saved immediately with their Mushaf, page and verse reference,
then restored after the ayah geometry loads on reopening. Clearing the selection
also clears its saved state. Writes are serialized so rapid selections retain the
latest choice; invalid or mismatched references are ignored. With no explicit
selection, the current playback highlight is remembered while playback is active.
Restoration does not restart audio or override the saved reading page.

During playback, bookmark and translation actions move into the audio section and
the separate ayah strip disappears. The combined section has no X button; tap-away
selection dismissal remains available. If a different ayah is selected, its
reference and a play-selected action appear alongside the existing playback
controls. Stopping audio restores the standalone ayah strip when selected.
Tests cover persisted selection/dismissal, rapid writes, malformed preferences,
independent selected-ayah and playing-ayah callbacks, small screens and both
orientations, including dock reversals while audio starts or stops.

## Fixed shared context bar

The reader now has two surfaces: main navigation and one shared ayah/audio bar.
The shared bar stays below navigation in portrait and to its outer right in
landscape. Selection and playback use the same component, dimensions and button
positions, so starting or stopping selected-ayah playback does not transfer
controls between surfaces. Inactive transport actions keep their slots but are
disabled. Both bars still collapse with the attached navigation tab.

A square Stop button calls the controller's full stop operation, including
preparation cancellation and repeat guards. There is no X in either state;
tap-away dismissal remains. When a different ayah is selected during playback,
tapping its reference plays that selection while the transport controls continue
to operate on current playback. Bookmark and translation target the selection.
Regression checks assert stable bar bounds and play/bookmark positions across
stop/start transitions, callback routing including Stop, both orientations and
small screens. All 98 tests pass; Flutter analysis is clean.

## Visible queue option and copy updates

Audio keeps its compact mode dropdown beside the ayah range on the same row.
Ayah range, Full surah and Surah queue remain available in every mode. Selecting
Surah queue opens its editor directly; saving selects queue mode, while dismissing keeps
the prior mode. A single-ayah active plan retains the saved queue for editing.
Explicit initial ayah ranges also take precedence over older saved ranges.
Regression tests cover these behaviors with and without active single-ayah audio,
queue order, persistence, cancellation and visibility at 320px width.

Quran Journey now displays the requested recitation hadith with attribution to
Prophet Muhammad and Sahih Muslim 804a, verified at https://sunnah.com/muslim:804a.
Its typography accommodates the longer passage. The Settings rating row uses the
existing navigation-row styling with a chevron, press feedback, button semantics
and the text "Tap to leave a review. Your support helps." The review action and
automatic review cadence are unchanged.

## Optional arrow-only controls

Settings > Quran Reader includes "Open controls with arrow only", off by default.
The preference persists locally and applies to both orientations. Enabling it
collapses the bars on returning to the reader, and subsequent launches start with
only the arrow tab visible. Selecting/restoring an ayah, opening an ayah bookmark,
page/background taps and playback updates do not reveal the bars in this mode.
Highlighting, tap-away deselection and playback continue independently. The tab
opens both navigation and the shared ayah/audio bar; existing timed hiding remains.

## iPhone dock edge placement

Removed the outer SafeArea that added iPhone insets to the dock's existing margins.
The collapsed tab now sits 8 logical pixels from the bottom edge in portrait
and 4 logical pixels from the right edge in landscape.
As controls expand, clearance interpolates to the greater of the required safe
inset and the small dock margin, rather than their sum. Expanded buttons remain
inside the safe region. The landscape tab stays vertically centred on the dock,
both collapsed and expanded, including on devices with a right-side inset.

Four regression cases simulate iPhone portrait/landscape insets, with and without
the context bar. They verify edge distance, expanded safe clearance, tab/button
taps, collapse restoration and unobstructed page swipes. All 104 tests pass and
Flutter analysis is clean. This was verified in Flutter widget tests, not on a
physical iPhone or a native iOS simulator.
