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

## v6 foldable portrait, landscape and book

Folded and unfolded continuous portrait now use the iPad-style height-only
zoom inside the safe horizontal reading band. At 70%, 85% and 100% the width
is identical. Height uses the full app viewport, including the bottom safe
inset. The floating collapsed tab ends 16 points above the iOS viewport edge.
Expanded controls consume the native bottom inset once.

Fully unfolded landscape starts a centred two-page row at the top of its
unobstructed viewport. Width sets the printed page height and both leaves
scroll vertically together. Horizontal drags turn the spread. Half-open book
keeps both pages at the smaller panel's proportional fit and leaves the hinge
clear. Regular phones and iPads keep their established geometry.

The previous simulator run (44509939240, attempt 2) recorded a 466 × 678
cover viewport and a 382-point reading width. Those older sidecars only
identify the resolved 84-point exclusion. Current QA sidecars include the
original MediaQuery padding and viewPadding, framework display features,
UIKit divisions with their source viewport, and cover state. The page's left
and right limits follow these inputs. No device width or camera inset is
assumed.

The rendered widget suite exercises the recorded asymmetric cover geometry
and a second inset combination, both editions, dock and contextual-control
animations, taps, focus and audio, scrolling and physical book panels. In the
limited native workflow, read the Duo PNGs with their matching layout JSON,
the settled iPad mini 80% portrait PNG, and the labelled comparison artifact.
The native checks cover endpoint zooms. Intermediate zooms are widget-tested.
