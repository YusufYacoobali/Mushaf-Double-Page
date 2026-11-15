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

Device follow-up: verify the iPad mini portrait geometry and dock on
hardware, and an actual iPhone Duo folded/unfolded if available. iOS does
not currently supply a reliable hinge geometry event in this project;
the wide-portrait phone layout uses the unobstructed window until such
geometry is provided.
