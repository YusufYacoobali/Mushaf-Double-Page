import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ReaderPageMode { single, spread }

enum DockPlacement { bottom, side }

enum ReaderSpreadLayout { centeredLandscape, separateRegions, widePortrait }

/// Window geometry with an explicit iPad portrait compatibility hint.
/// Width alone cannot distinguish an iPad mini from an unfolded phone.
class ReaderLayout {
  const ReaderLayout({
    required this.pageMode,
    required this.spreadLayout,
    required this.dockPlacement,
    required this.usableContentBounds,
    required this.pageRegions,
    required this.controlsRegion,
    required this.safeRegions,
    this.fullWidthPortrait = false,
  });
  final ReaderPageMode pageMode;
  final ReaderSpreadLayout spreadLayout;
  final DockPlacement dockPlacement;
  final Rect usableContentBounds;

  /// Left-to-right regions for separated and wide-portrait spreads. Centered
  /// landscapes use [usableContentBounds] as one continuous spread surface.
  final List<Rect> pageRegions;
  final Rect controlsRegion;
  final List<Rect> safeRegions;

  /// Conventional portrait phones retain v4's edge-to-edge page and dock.
  /// Insets belong to the controls themselves, not their enclosing viewport.
  final bool fullWidthPortrait;
  bool get singlePage => pageMode == ReaderPageMode.single;
  bool get bottomDock => dockPlacement == DockPlacement.bottom;

  static ReaderLayout resolve({
    required Size size,
    EdgeInsets padding = EdgeInsets.zero,
    List<DisplayFeature> displayFeatures = const [],
    double pageAspectRatio = 721 / 1058,
    bool preserveLegacyIPadPortrait = false,
    bool iosPhoneWidePortrait = false,
  }) {
    final regions = safeDisplayRegions(size, padding, displayFeatures);
    final largest = regions.reduce(
      (a, b) =>
          a.size.longestSide * a.size.shortestSide >=
              b.size.longestSide * b.size.shortestSide
          ? a
          : b,
    );
    // A panel on one side of a physical hinge owns the entire dock. Never put a
    // row of buttons across the hinge, even when two pages are visible.
    final sameRow =
        regions
            .where(
              (r) =>
                  (r.top - largest.top).abs() < 1 &&
                  (r.bottom - largest.bottom).abs() < 1,
            )
            .toList()
          ..sort((a, b) => a.left.compareTo(b.left));
    final controls = sameRow.length >= 2 ? sameRow.last : largest;
    final landscape = size.width > size.height;
    // Original iPad reading was always one full-width page in portrait.
    // Do not apply the unfolded-phone width threshold to an iPad window.
    final legacyIPadPortrait = preserveLegacyIPadPortrait && !landscape;
    final bottom = (!landscape || sameRow.length >= 2) && controls.width >= 300;
    final pageBounds = <Rect>[];
    final candidates = sameRow.length >= 2
        ? [sameRow.first, sameRow.last]
        : [largest];
    final centeredLandscape = landscape && candidates.length == 1;
    for (final region in candidates) {
      // Keep spread planning stable as controls appear and disappear. A single
      // page with a bottom dock uses the full safe region below, with overlays.
      final right = !bottom && region == controls && !centeredLandscape
          ? 140.0
          : 0.0;
      final bottomGutter = bottom ? 142.0 : 0.0;
      pageBounds.add(
        Rect.fromLTRB(
          region.left,
          region.top,
          math.max(region.left + 1, region.right - right),
          math.max(region.top + 1, region.bottom - bottomGutter),
        ),
      );
    }
    final physicalPair = pageBounds.length == 2;
    final spreadLayout = physicalPair
        ? ReaderSpreadLayout.separateRegions
        : centeredLandscape
        ? ReaderSpreadLayout.centeredLandscape
        : ReaderSpreadLayout.widePortrait;
    final combined = physicalPair
        ? pageBounds.first.expandToInclude(pageBounds.last)
        : pageBounds.first;
    final spreadRegions = physicalPair
        ? pageBounds
        : [
            Rect.fromLTRB(
              combined.left,
              combined.top,
              combined.center.dx - .5,
              combined.bottom,
            ),
            Rect.fromLTRB(
              combined.center.dx + .5,
              combined.top,
              combined.right,
              combined.bottom,
            ),
          ];
    // The unfolded iPhone Duo's inner screen is 669 logical px wide in
    // portrait, below the generic 720 px threshold. Its two readable leaves
    // fit at this width, while iPads still retain their legacy portrait mode.
    // Do not lower the breakpoint for Android tablets or split-screen windows.
    final minimumWidth = landscape
        ? 600.0
        : (iosPhoneWidePortrait && !preserveLegacyIPadPortrait ? 640.0 : 720.0);
    final canSpread =
        !legacyIPadPortrait &&
        (physicalPair || largest.width >= minimumWidth) &&
        spreadRegions.every(
          (r) =>
              r.width >= (landscape ? 200 : 280) &&
              r.height >= 260 &&
              math.min(r.width, r.height * pageAspectRatio) >=
                  (landscape ? 180 : 240),
        );
    final single = (bottom ? candidates : pageBounds).reduce(
      (a, b) => a.width * a.height >= b.width * b.height ? a : b,
    );
    // v4 placed the centred landscape Row across the full viewport, with the
    // toolbar overlaid. Insets still position controls independently. If an
    // obstruction further partitions that viewport, keep the spread inside its
    // unobstructed region instead.
    final originalLandscapeBounds =
        centeredLandscape &&
        regions.length == 1 &&
        largest == safeDisplayRegions(size, padding, const []).single;
    final originalPortraitBounds =
        !landscape &&
        (size.width < 600 || legacyIPadPortrait) &&
        regions.length == 1 &&
        largest == safeDisplayRegions(size, padding, const []).single;
    final singleBounds = originalPortraitBounds ? Offset.zero & size : single;
    final spreadBounds = originalLandscapeBounds
        ? Offset.zero & size
        : combined;
    return ReaderLayout(
      pageMode: canSpread ? ReaderPageMode.spread : ReaderPageMode.single,
      spreadLayout: spreadLayout,
      dockPlacement: bottom ? DockPlacement.bottom : DockPlacement.side,
      usableContentBounds: canSpread ? spreadBounds : singleBounds,
      pageRegions: List.unmodifiable(
        canSpread ? spreadRegions : [singleBounds],
      ),
      controlsRegion: controls,
      safeRegions: List.unmodifiable(regions),
      fullWidthPortrait: originalPortraitBounds,
    );
  }
}

/// Trim safe edges, then partition around obstructing/separating display
/// features. A flat, zero-width fold is seamless; a half-open fold separates.
/// Interior cutouts conservatively split a region rather than cover Quran text.
List<Rect> safeDisplayRegions(
  Size size,
  EdgeInsets padding,
  List<DisplayFeature> features,
) {
  var regions = [
    Rect.fromLTRB(
      padding.left,
      padding.top,
      math.max(padding.left + 1, size.width - padding.right),
      math.max(padding.top + 1, size.height - padding.bottom),
    ),
  ];
  for (final feature in features) {
    final b = feature.bounds;
    final separating =
        feature.type == DisplayFeatureType.hinge ||
        feature.type == DisplayFeatureType.cutout ||
        (feature.type == DisplayFeatureType.fold &&
            feature.state == DisplayFeatureState.postureHalfOpened);
    if (!separating) continue;
    final next = <Rect>[];
    for (final r in regions) {
      final crosses =
          b.left < r.right &&
          b.right >= r.left &&
          b.top < r.bottom &&
          b.bottom >= r.top;
      if (!crosses) {
        next.add(r);
        continue;
      }
      if (b.height >= b.width && b.height > 0) {
        if (b.left > r.left) {
          next.add(Rect.fromLTRB(r.left, r.top, b.left, r.bottom));
        }
        if (b.right < r.right) {
          next.add(Rect.fromLTRB(b.right, r.top, r.right, r.bottom));
        }
      } else {
        if (b.top > r.top) {
          next.add(Rect.fromLTRB(r.left, r.top, r.right, b.top));
        }
        if (b.bottom < r.bottom) {
          next.add(Rect.fromLTRB(r.left, b.bottom, r.right, r.bottom));
        }
      }
    }
    if (next.isNotEmpty) regions = next;
  }
  return regions;
}

/// Rightmost available region for slide-in panels; safe on either side of a
/// separating hinge, with dimensions recalculated on every window resize.
Rect navigationRegion(
  Size size,
  EdgeInsets padding,
  List<DisplayFeature> features,
) {
  final regions = safeDisplayRegions(size, padding, features);
  regions.sort((a, b) => b.right.compareTo(a.right));
  return regions.first;
}

double navigatorPanelWidth(Size window, Rect region) {
  final landscape = window.width > window.height;
  final desired = landscape
      ? (window.width * .55).clamp(420.0, 480.0)
      : window.width >= 600
      ? (window.width * .5).clamp(420.0, 560.0)
      : 320.0;
  final cap = region.width >= 600 ? region.width * .65 : region.width;
  return math.min(desired, cap);
}
