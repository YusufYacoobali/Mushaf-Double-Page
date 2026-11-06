# v5 responsive layouts and UX validation — 6 November 2026

Implemented on the existing `v5` worktree based on `ac7c290`. The remote branch
was fetched before editing and contained no newer commits. This work does not
merge into `main` or change the audio queue, recording repository, Bismillah
verification policies, Tasbeeh counts, dhikr, feedback or persistence.

## Adaptive reader rule

`ReaderLayout.resolve` uses the current `LayoutBuilder` constraints, safe insets,
`MediaQuery.displayFeatures`, and the selected edition's native image aspect
ratio. `pageMode`, `dockPlacement`, page regions and the controls region are
separate decisions.

1. Trim safe insets, then partition around physical hinges, half-open folds and
   obstructing cutouts. A flat zero-width fold remains seamless. A horizontal
   separator uses one unobstructed screen instead of stacking a sideways spread.
2. Place controls in one safe region. Use the bottom dock in portrait/square
   windows, or in one sufficiently wide pane of a hinged display. Its region must
   be at least 300 logical pixels wide. Other windows use the side dock.
3. Use stable gutters when planning and displaying spreads: 142 logical pixels
   at the bottom or 140 at the right. Single pages with a bottom dock use their
   full safe region; controls overlay the page instead of permanently reserving
   expanded-toolbar space. Revealing/hiding controls does not change the page
   mode or resize the single page. Single pages with a side dock retain its gutter.
4. For a seamless display, a spread needs a safe region at least **720 logical
   pixels wide in portrait/square windows**, or **600 in landscape**. Two separate
   side-by-side safe regions can also qualify without that overall-width gate.
5. After gutters, **both** page regions must have height at least **260**, width
   at least **280 in portrait/square** or **200 in landscape**, and an
   aspect-correct fitted width of at least **240 in portrait/square** or **180 in
   landscape**. Fitted width is `min(region.width, region.height * imageAspect)`.
   Otherwise the reader uses a single page in the largest usable region.

All dimensions are logical pixels. Source aspects remain `721 / 1058` for
Indo-Pak and `2096 / 3008` for Madani. Page images/highlight coordinates maintain
those proportions; the old single-page stretching is removed. Toolbar scale
preferences remain separate for single pages and spreads. Spreads retain vertical
scrolling at larger zoom levels and RTL horizontal page turns. Layout changes
reset a transient pinch transform to the new geometry while retaining saved zoom
percentages and their mode-specific limits.

Compact-phone follow-up: at 320 × 568 without safe insets and the saved 80% zoom,
the single page is approximately 310 px wide for Indo-Pak and 317 px for Madani,
instead of being constrained by the former permanent 142 px bottom gutter.
Regressions require at least 95% of viewport width for both editions, preserve
the native aspect ratio, and verify identical bounds and focused page with the
dock collapsed, expanded and collapsed again. Safe insets still apply; spread
gutters and breakpoints are unchanged.

| Window | Default page mode | Dock |
| --- | --- | --- |
| 320 × 568 | Single | Bottom |
| 390 × 844 | Single | Bottom |
| 844 × 390 | Spread | Side |
| 600 × 840 | Single | Bottom |
| 900 × 900 | Spread | Bottom |
| 951 × 669 | Spread | Side |
| 1200 × 800 | Spread | Side |
| 340 × 700 split-screen | Single | Bottom |
| 500 × 300 split-screen | Single | Side |
| 950 × 669 with a vertical 30 px hinge at x=460 | Spread, one page per pane | Bottom, right pane |

Insets and obstruction geometry can change these outcomes. The rule never uses a
model name, device category or physical display resolution.

## Page preservation and secondary screens

`ReaderPaging` owns the `PageController`, focused physical file page and callback
generation. Touching either spread page records the focused page without adding a
reading visit. Reconfiguration selects the spread containing that page or returns
to that exact single page. Retired controllers are disposed after detachment;
callbacks carrying their old generation cannot change or save the current page.
An edition change also replaces the controller before asynchronous history work.

The existing printed spread pairing is preserved: even-numbered file page on the
right, following odd-numbered page on the left. The zero slot at the beginning
and any missing final partner are blank, never duplicate images. Single-page
indices map to file pages 1–851 / 1–624 with no duplicate page 1. Bookmark jumps,
translation ranges and audio selections use physical pages/visible spreads.

Reader activity adopts a new visible set without recording an extra visit on a
layout change. Audio-follow identity excludes page mode: folding cannot refollow
an already consumed ayah notification after a manual move. New playback ayahs
still follow normally. Selection, bookmark and highlight state stay in the reader
State object rather than in a replaced controller.

Settings, Quran Journey, translation and Tasbeeh use `AdaptiveSurface` to stay
inside one unobstructed region and cap screen content at 900 logical pixels.
Tasbeeh receives only that resizing wrapper. Bottom sheets cap width at 640;
dialogs at 560. Open bookmark sheets recalculate height on resize. Translation
app-bar titles use constrained text and a text-scale-aware toolbar height. Existing
themes, scrolling, reduced-motion behavior and business logic remain.

## Surah/Juz navigator

Normal portrait phones retain 320 px width. Landscape width is
`clamp(window.width * .55, 420, 480)`. Portrait windows at least 600 px wide use
`clamp(window.width * .5, 420, 560)`. The result is clamped to the safe panel region;
regions at least 600 px wide also cap it to 65% of that region.

The dialog explicitly anchors to the right display pane. Safe insets are removed
from its local MediaQuery after positioning so the scrollbar does not apply them
twice. The existing slide/fade, colors, selector and draggable right scrollbar
remain. Both lists keep independent state. Resizing recomputes row extents using
actual text width/text scale and preserves the first visible row and within-row
fraction. Number badges grow for scaled text, titles wrap naturally and the
trailing indicator remains aligned.

## Review prompt and daily reminder

The independently tested rule is:

```dart
(launch >= 1 && launch <= 5) ||
(launch >= 15 && (launch - 15) % 10 == 0)
```

The existing `review_prompt_launch_count` key is incremented once per process
session, without resetting existing totals. Repeated schedule calls, navigation,
rebuilds and resume do not increment it. The delay remains two minutes. Background
or inactive/system-prompt transitions cancel that launch's automatic prompt;
returning does not restart it. At the deadline, covered routes, non-reader pages,
loading/recovery/buffering, offline downloads and persistent audio errors suppress
it without queuing a later surprise. Rate stores `review_prompt_rate_chosen` and
suppresses future automatic prompts. Not now keeps the normal schedule. Settings
rating still opens the existing published store listing independently. Native
review requests retain platform availability/quota handling and do not fall back
to unexpected automatic store navigation.

The compact daily card contains the unchanged intercession hadith, attribution and
Sahih Muslim 804a reference, with the existing charcoal/bronze treatment. It has no
introductory slogan, streak heading or decorative sparkle. Its dismiss button is
pinned while long/scaled text scrolls. Its width is capped at 480 and height at
half its safe pane, clearing hinges. The existing once-daily decision and
nine-second automatic dismissal are unchanged. Journey streak information stays
in the noncompact card and Journey screen.

## Validation

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: **263 tests passed**.
- `git diff --check`: clean.
- Targeted Flutter widget-rendering diagnostic: three navigator sizes plus the
  minimal reminder, using the actual Inter and Material icon fonts. This is
  Flutter test rendering, not native device validation.

Regressions cover both editions; the table's window sizes; safe insets, vertical
hinges, half-open/flat folds and cutouts; RTL order and every file exactly once;
focused-page/selection preservation; stale callbacks; resizing during animated
navigation; no extra reading visit on folding; audio-follow identity; open modal
resizing; secondary screens; 1.4–1.8 text scaling and both themes; the full launch
schedule, migration, timing, background cancellation, modal suppression, saved
Rate choice and independent manual rating. Existing audio/Bismillah and Tasbeeh
regressions remain in the full suite.

To recreate the widget-rendering snapshots:

```bash
RESPONSIVE_SCREENSHOTS=/tmp/v5-responsive-previews \
  flutter test --no-pub tool/responsive_visual_smoke_test.dart
```

## Platform checks and remaining device validation

Android has no orientation lock in its activity manifest; resize/screen-layout
configuration changes are already handled. iOS declares all four orientations,
targets iPhone/iPad and has no `UIRequiresFullScreen` restriction. No platform
orientation changes were necessary.

The reviewed Flutter 3.38.1 [iOS embedding](https://github.com/flutter/flutter/blob/3.38.1/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm)
updates window dimensions and UIKit safe-area insets. The inspected public iOS 26
[UIScreen](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS26.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIScreen.h)
and [UIWindowScene](https://github.com/xybp888/iOS-SDKs/blob/master/iPhoneOS26.0.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIWindowScene.h)
header mirror provides no hinge geometry API. There is no iOS SDK/device in this
workspace with which to validate a newer API. No speculative native hinge bridge
or device-name special case is introduced. iOS currently adapts using window
constraints and safe insets, and honors display features if supplied by Flutter.
A seamless inner display uses its full safe width; an unreported physical hinge
cannot be inferred from size alone.

`flutter devices --machine` exposes only Linux; no Android/iOS emulator, simulator
or physical device is attached. Validate real fold/unfold posture events and
hinge/cutout reporting on Android, iPhone cover/inner display transitions including
the requested iPhone Duo, iPad split view/Stage Manager, multitasking, live audio
highlight/follow behavior and accessibility on devices. This work does not claim
certification of an untested device or an unavailable iOS hinge API.
