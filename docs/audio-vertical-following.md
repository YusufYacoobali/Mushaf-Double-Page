# Follow the recited ayah within its page

`AudioPageFollower` still chooses the page. After `ReaderPaging.goTo` completes,
the reader requests a vertical reveal on the laid-out destination. Position ticks
do not create further requests for the same session/repeat/ayah/Mushaf identity.

`AudioVerticalFollower` owns request cancellation and gesture suspension.
`AudioVerticalViewport` owns the page's transformation or scroll controller and
registers its actual viewport and printed-page render boxes. Normalized rectangles
come from `AyahRectIndex.rectsFor`; their render transforms include page sizing,
InteractiveViewer zoom, scrolling, and the left/right spread location. Visibility
is intersected with the page clip and safe screen bounds. Expanded reader controls
also reduce the usable area where they overlap the page.

A line is meaningfully visible when its clipped intersection clears the small
edge margin and covers enough of its height and width. Any visible line of the
ayah, including one on the other visible page, prevents movement. If none is
visible, the nearest line is revealed with 16 logical pixels of breathing room,
clamped to the available extent. Missing rectangles and horizontal-only clipping
do not cause vertical movement. No automatic centring occurs.

Portrait pages retain the existing full-width, height-only toolbar geometry.
The viewer's matrix changes only its vertical translation; scale and horizontal
translation remain exact. Vertical panning is enabled only when the printed page
overflows its usable viewport. Safe-area/control boundary margins allow an ayah
under an overlay to be revealed without changing page geometry. Normal horizontal
swipes still navigate pages; two-finger scaling remains with InteractiveViewer.
Tap hit testing uses the transformed printed surface as well.

Centred landscape spreads share one managed scroll controller. Separate page
regions, including foldables and wide portrait spreads, have independent
controllers. Revealing an ayah on one independent page leaves the other still.

Reveals animate for 250 ms with ease-out motion, or apply immediately when
`AppMotion.reduced` is true. Pointer interaction, manual scrolling and page changes
cancel active work. New ayahs received during interaction can resume after the
gesture/fling ends and 650 ms of idle time. An already-consumed ayah never pulls a
manually moved page back. Rotation, resize, Mushaf/zoom changes, a new playback
selection, covered routes and backgrounding reject stale work. A controller's
animation is not cancelled by unrelated parent rebuilds or audio position ticks.

The implementation adds no audio subscriptions or playback/timing changes, UI
settings, image reloads or persisted scroll state. Controllers and timers are
released with their reader/page widgets.

Validation includes pure visibility/extent tests and Flutter widget regressions
for both Mushafs, portrait and centred/separate landscape pages, meaningful
partial visibility, exact zoom preservation, safe areas and dock overlap,
horizontal navigation and transformed taps, manual interaction, reduced motion,
page-turn completion, rotation during navigation, foldable regions and rapid
ayah changes. Existing reader geometry, navigation, audio and gesture tests remain
part of the full regression suite.

Validation on 7 November 2026: `flutter analyze --no-pub` reported no issues;
the full Flutter suite passed **448 tests** with two existing optional checks
skipped. The 29 vertical-follow tests also passed independently, and
`git diff --check` was clean.
