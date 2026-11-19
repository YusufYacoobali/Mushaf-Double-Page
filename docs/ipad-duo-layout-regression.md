# iPad portrait compatibility + iPhone Duo adaptive spread

## Diagnosis (v5 against main)

The main branch's reader uses OrientationBuilder: every portrait window,
including an iPad mini, renders one Quran page with full viewport width and
viewport height multiplied by the portrait zoom preference. The bottom toolbar
overlays the full viewport.

v5's ReaderLayout.resolve chose a two-page spread in any unobstructed portrait
window at least 720 logical pixels wide when both page regions passed the
minimum-size checks. An iPad mini's 744 x 1133 portrait window crossed that
threshold, shrinking its Quran text to two small pages and changing the
original portrait formatting.

## Fix on v5

* At startup, UIKit reports the iOS hardware idiom via the
  mushaf_two_page/device isIPad method channel. The result is resolved before
  the first reader frame, not inferred from viewport width.
* Every iPad portrait/square window retains the single, full-width,
  height-only-zoomed page with bottom controls in screen coordinates, exactly
  as main did. iPad landscape keeps the original centered facing-page Row.
* iPhone (including Duo cover and wide unfolded display) and Android retain
  the v5 width/hinge-safe spread selection. An unfolded wide portrait window
  can show one page on each side; a narrow cover uses one page.
* ReaderPaging continues to retain the exact focused file page across
  portrait/landscape, resize and unfold transitions. No audio, bookmark or
  zoom preference migrations are needed.

## Validation

Run:
`flutter test test/ios_device_idiom_test.dart test/ipad_duo_reader_regression_test.dart`
then `flutter test` and `flutter analyze`.

Coverage includes iPad mini (744 x 1133), larger iPads, square windows,
both Mushaf editions, dock toggles, exact page frames, RTL facing pages,
page focus preservation and unfolded 900 x 900 phone layouts. Existing v5
hinge and split-screen tests remain unchanged.

## v6: foldable zoom and floating controls

Foldable 100% means the largest proportional page that fits the full safe
display region. For one page, its width is
`min(safeWidth, safeHeight * pageAspectRatio)`; lower zoom values scale both
dimensions from that maximum. An unfolded portrait Duo uses one page.
Unfolded landscape uses two facing pages. A physical separating hinge gives
each book page its own safe panel, with equal page sizes on both sides.

The app's navigation bar and contextual audio/selection controls float over
the pages. They do not subtract height or width from the fit. Opening,
closing, or expanding controls must never resize or shift a page. Native
safe insets and separating display regions still protect cameras, system
areas, and physical hinges. A remaining margin on the non-limiting axis is
expected; page artwork is not distorted to fill both axes.

Ordinary phones and tablets keep their previous geometry, including iPad
portrait's full-width, height-only zoom. The native iPad idiom guard takes
precedence over foldable hints.

`foldable_layout_fixes_test.dart` checks both Mushaf editions at folded and
unfolded portrait/landscape sizes, real dock transitions and contextual
controls, proportional zoom, and physical book panels. Existing phone and
iPad regressions remain required. Native verification uses only the proven
Duo minimum/maximum captures in four postures and iPad mini portrait; those
screenshots do not establish native intermediate-zoom or iPad-landscape
coverage. A capture's filename is a requested zoom, not proof of the zoom
actually rendered.
