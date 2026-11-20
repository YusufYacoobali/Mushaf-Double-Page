# Follow the recited ayah within its page

Current behaviour on `v7`, updated 20 November 2026.

## Ownership and page navigation

[`AudioPageFollower`](../lib/utils/audio_page_follower.dart) chooses the reading
page. [`ReaderPaging`](../lib/utils/reader_paging.dart) owns page navigation and
turn completion. After navigation settles, the follower requests a vertical
reveal on that specific page, using its actual laid-out geometry.

[`AudioVerticalFollower`](../lib/utils/audio_vertical_follower.dart) owns reveal
requests, cancellation and gesture suspension.
[`AudioVerticalViewport`](../lib/components/audio_vertical_viewport.dart) owns
the viewport's scroll/transformation controller and render-box measurements.
Normalized ayah rectangles come from
[`AyahRectIndex`](../lib/utils/ayah_rect_index.dart).

Playback never waits for a page turn, layout or vertical animation. Position
ticks do not repeatedly reveal the same session/repeat/ayah/Mushaf identity.

## Which layouts follow vertically

| Reader layout | Behaviour |
| --- | --- |
| Single page, including portrait and narrow-window single-page fallbacks | Automatic vertical following is disabled. Controls and safe insets add no audio-following boundary margin. |
| Two pages sharing a scroll viewport | Reveal the chosen page's ayah by moving the shared spread, within its available scroll extent. |
| Two pages in separate scrollable regions | Reveal in the chosen page's viewport; the other independent viewport stays still. Movement remains bounded by the available extent. |
| Fully fitted book/region-fit two-page content | These paths have no scroll view, so their movement range is zero. Following does not create scrolling for them. |

The policy is based on **single-page versus two-page layout**, not a platform
name or orientation alone. An explicit foldable book posture can show two pages
even in a tall window; its fitted content still has the extent limit above.

### Single-page geometry

[`QuranPageView.singlePage`](../lib/pages/page_view.dart) sets `followAudio: false`.
Its printed page fits the viewport height under the supported toolbar/pinch
limits. At 100%, recitation leaves the fitted page in its original position and
adds no top/bottom scrolling space. Normal centring at smaller toolbar scales
remains part of page sizing.

Manual pinch zoom and natural panning within the scaled scene remain available,
along with page-turn gestures and transformed tap coordinates. The follower
still receives interaction notifications, but this viewport registers no surface
for automatic vertical movement. Disabling following on an existing transformed
viewport removes offsets into the old added clearance while preserving zoom,
horizontal translation and vertical positioning within the natural scene bounds.

## Whole-ayah targeting in two-page views

Measurements use the painted page after layout and scrolling, clipped to the
viewport and safe screen bounds. The actual expanded control-bar rectangle is
used when it overlaps the target; an empty surrounding container does not count
as an obstruction. The viewport chooses a reachable clear vertical band where
one is available.

- Combine all horizontally reachable rectangles for the ayah on the chosen page.
  One visible line alone does not make a multi-line ayah fully visible.
- If that full span already fits inside the reading band with its margin, keep
  the current position. Otherwise centre the span when it fits, clamped to the
  available movement.
- Use up to 16 logical pixels of breathing room. Reduce the margin when the ayah
  nearly fills the reading band.
- If the ayah is taller than the band, bring its beginning/first complete lines
  towards the top. The app cannot show every line at once or follow later lines
  precisely without additional timing data.
- Missing rectangles and clipping that can only be fixed horizontally do not
  cause vertical movement. Unavailable scroll extent still limits the reveal.

Scrollable spread paths can add trailing clearance for lines near the bottom.
Clearance is retained until the relevant geometry changes so a reveal does not
immediately snap back. Layout is allowed to apply new padding before measuring
again. Fitted single-page views are excluded from this clearance policy.

## Ayahs spanning pages

Keep the currently focused portion of a straddling ayah when it is present; prefer
another visible leaf over turning back to the ayah's first indexed page. Vertical
following targets the portion on the page selected by `AudioPageFollower`.

Automatic page changes remain driven by ayah changes. If an ayah continues onto
the next page, there is no new turn at the exact boundary word during that ayah;
a later ayah can trigger navigation when it requires a page outside the current
view. Word-timed page changes and continuous movement through long ayahs remain
deferred work.

## Motion and user interaction

Reveals animate for 250 ms with ease-out motion, or apply immediately when
`AppMotion.reduced` is true. Pointer interaction, manual scrolling and page
changes cancel active work. New ayahs received during interaction can resume
after the gesture/fling ends and 650 ms of idle time. An already-consumed ayah
does not pull a manually moved page back.

Rotation, resize, Mushaf/zoom changes, a new playback selection, covered routes
and backgrounding invalidate stale work. Unrelated parent rebuilds and audio
position ticks do not cancel a valid reveal. Controllers and timers are released
with their owning reader/page widgets. Vertical following does not pause, stop
or seek audio and does not introduce a separate audio-position subscription.

## Verification

Relevant regressions cover full-ayah containment, oversized ayahs, obstruction
clearance, current-page preference, manual interaction, reduced motion and
navigation cancellation. Single-page checks cover fixed geometry at 100%, real
control toggles, safe insets, valid manual pinch/pan and transformed taps across
phone, tablet and foldable layouts.

```sh
flutter test --no-pub test/audio_vertical_follower_test.dart test/audio_vertical_viewport_test.dart test/audio_page_follower_test.dart test/foldable_layout_fixes_test.dart test/adaptive_reader_test.dart
flutter analyze --no-pub
flutter test --no-pub
```

Recorded Flutter verification for
[`a6ae6a6`](https://github.com/YusufYacoobali/Mushaf-Double-Page/commit/a6ae6a6ee8e0a248447a7afad535cf2d82585cb7)
on 20 November 2026: 107 focused tests passed; the full suite passed 592 tests with
two existing skips; static analysis reported no issues. This is a dated Flutter
result, not a claim of native-device or simulator verification for later commits.
