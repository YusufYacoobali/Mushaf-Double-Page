import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ReaderPageMode { single, spread, dualScreenBook }

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
    this.centerSideDock = false,
    this.fitPagesToViewport = false,
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
  final bool centerSideDock;

  /// Foldable pages fit the safe display, behind the floating controls.
  /// iPads retain their v5 geometry.
  final bool fitPagesToViewport;
  bool get singlePage => pageMode == ReaderPageMode.single;
  bool get bottomDock => dockPlacement == DockPlacement.bottom;

  static ReaderLayout resolve({
    required Size size,
    EdgeInsets padding = EdgeInsets.zero,
    List<DisplayFeature> displayFeatures = const [],
    double pageAspectRatio = 721 / 1058,
    bool preserveLegacyIPadPortrait = false,
    bool iosPhoneWidePortrait = false,
    bool foldedCover = false,
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
    final fitPages =
        !preserveLegacyIPadPortrait &&
        (foldedCover ||
            (iosPhoneWidePortrait && size.shortestSide >= 600) ||
            displayFeatures.any(
              (f) =>
                  f.type == DisplayFeatureType.fold ||
                  f.type == DisplayFeatureType.hinge,
            ));
    // iPad compatibility takes precedence over every foldable hint. A fold or
    // hinge (including a flat fold) identifies segmented Android devices;
    // iOS supplies its real division regions through the native bridge.
    final foldable =
        !preserveLegacyIPadPortrait &&
        (iosPhoneWidePortrait ||
            displayFeatures.any(
              (f) =>
                  f.type == DisplayFeatureType.fold ||
                  f.type == DisplayFeatureType.hinge,
            ));
    final halfOpened = displayFeatures.where(
      (f) =>
          (f.type == DisplayFeatureType.fold ||
              f.type == DisplayFeatureType.hinge) &&
          f.state == DisplayFeatureState.postureHalfOpened,
    );
    final safeBounds = safeDisplayRegions(size, padding, const []).single;
    final book =
        foldable &&
        sameRow.length >= 2 &&
        halfOpened.any(
          (f) =>
              f.bounds.height > f.bounds.width &&
              f.bounds.top <= safeBounds.top &&
              f.bounds.bottom >= safeBounds.bottom &&
              f.bounds.left > safeBounds.left &&
              f.bounds.right < safeBounds.right,
        );
    final tabletop =
        foldable &&
        halfOpened.any(
          (f) =>
              f.bounds.width > f.bounds.height &&
              f.bounds.left <= safeBounds.left &&
              f.bounds.right >= safeBounds.right &&
              f.bounds.top > safeBounds.top &&
              f.bounds.bottom < safeBounds.bottom,
        );
    final foldablePortrait = foldable && !landscape && !book;
    // Original iPad reading was always one full-width page in portrait.
    // Do not apply the unfolded-phone width threshold to an iPad window.
    final legacyIPadPortrait = preserveLegacyIPadPortrait && !landscape;
    final bottom =
        (!landscape || (sameRow.length >= 2 && !book)) && controls.width >= 300;
    final pageBounds = <Rect>[];
    final candidates = sameRow.length >= 2
        ? [sameRow.first, sameRow.last]
        : [largest];
    final centeredLandscape = landscape && candidates.length == 1;
    for (final region in candidates) {
      // Floating controls overlay foldable pages: 100% fits the full safe
      // display or physical panel, independent of the dock's current size.
      // Preserve the existing gutters for non-foldable spread planning.
      final right =
          !fitPages && !bottom && region == controls && !centeredLandscape
          ? 140.0
          : 0.0;
      final bottomGutter = !fitPages && bottom ? 142.0 : 0.0;
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
    final minimumWidth = landscape ? 600.0 : 720.0;
    final canSpread =
        !legacyIPadPortrait &&
        !tabletop &&
        !(foldedCover && !preserveLegacyIPadPortrait) &&
        !foldablePortrait &&
        (physicalPair || largest.width >= minimumWidth) &&
        spreadRegions.every(
          (r) =>
              r.width >= (landscape ? 200 : 280) &&
              r.height >= 260 &&
              math.min(r.width, r.height * pageAspectRatio) >=
                  (landscape ? 180 : 240),
        );
    final single = (bottom && !fitPages ? candidates : pageBounds).reduce(
      (a, b) => a.width * a.height >= b.width * b.height ? a : b,
    );
    // v4 placed the centred landscape Row across the full viewport, with the
    // toolbar overlaid. Insets still position controls independently. If an
    // obstruction further partitions that viewport, keep the spread inside its
    // unobstructed region instead.
    final originalLandscapeBounds =
        !fitPages &&
        centeredLandscape &&
        regions.length == 1 &&
        largest == safeDisplayRegions(size, padding, const []).single;
    final originalPortraitBounds =
        !fitPages &&
        !landscape &&
        (size.width < 600 || legacyIPadPortrait) &&
        regions.length == 1 &&
        largest == safeDisplayRegions(size, padding, const []).single;
    final singleBounds = originalPortraitBounds ? Offset.zero & size : single;
    final spreadBounds = originalLandscapeBounds
        ? Offset.zero & size
        : combined;
    return ReaderLayout(
      pageMode: canSpread
          ? (book ? ReaderPageMode.dualScreenBook : ReaderPageMode.spread)
          : ReaderPageMode.single,
      spreadLayout: spreadLayout,
      dockPlacement: bottom ? DockPlacement.bottom : DockPlacement.side,
      usableContentBounds: canSpread ? spreadBounds : singleBounds,
      pageRegions: List.unmodifiable(
        canSpread ? spreadRegions : [singleBounds],
      ),
      controlsRegion: controls,
      safeRegions: List.unmodifiable(regions),
      fullWidthPortrait: originalPortraitBounds,
      fitPagesToViewport: fitPages,
      centerSideDock:
          landscape &&
          (preserveLegacyIPadPortrait ||
              foldedCover ||
              (iosPhoneWidePortrait && size.shortestSide >= 600) ||
              displayFeatures.any(
                (f) =>
                    f.type == DisplayFeatureType.fold ||
                    f.type == DisplayFeatureType.hinge,
              )),
    );
  }
}

/// Trim safe edges, then partition around obstructing/separating display
/// features. A flat, zero-width fold is seamless; a half-open fold separates.
/// Small camera cutouts are covered by safe insets, not projected into a
/// full-height/width obstruction. Only a feature spanning a region divides it.
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
      final vertical =
          b.height > b.width && b.top <= r.top && b.bottom >= r.bottom;
      final horizontal =
          b.width > b.height && b.left <= r.left && b.right >= r.right;
      if (vertical) {
        if (b.left > r.left) {
          next.add(Rect.fromLTRB(r.left, r.top, b.left, r.bottom));
        }
        if (b.right < r.right) {
          next.add(Rect.fromLTRB(b.right, r.top, r.right, r.bottom));
        }
      } else if (horizontal) {
        if (b.top > r.top) {
          next.add(Rect.fromLTRB(r.left, r.top, r.right, b.top));
        }
        if (b.bottom < r.bottom) {
          next.add(Rect.fromLTRB(r.left, b.bottom, r.right, r.bottom));
        }
      } else {
        next.add(r);
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
