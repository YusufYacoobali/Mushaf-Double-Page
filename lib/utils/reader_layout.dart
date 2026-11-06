import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ReaderPageMode { single, spread }

enum DockPlacement { bottom, side }

/// Window geometry, independent of device names and physical pixel resolution.
class ReaderLayout {
  const ReaderLayout({
    required this.pageMode,
    required this.dockPlacement,
    required this.usableContentBounds,
    required this.pageRegions,
    required this.controlsRegion,
    required this.safeRegions,
  });
  final ReaderPageMode pageMode;
  final DockPlacement dockPlacement;
  final Rect usableContentBounds;

  /// Left-to-right physical regions; a spread's first Quran page is on the right.
  final List<Rect> pageRegions;
  final Rect controlsRegion;
  final List<Rect> safeRegions;
  bool get singlePage => pageMode == ReaderPageMode.single;
  bool get bottomDock => dockPlacement == DockPlacement.bottom;

  static ReaderLayout resolve({
    required Size size,
    EdgeInsets padding = EdgeInsets.zero,
    List<DisplayFeature> displayFeatures = const [],
    double pageAspectRatio = 721 / 1058,
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
    final bottom = (!landscape || sameRow.length >= 2) && controls.width >= 300;
    final pageBounds = <Rect>[];
    final candidates = sameRow.length >= 2
        ? [sameRow.first, sameRow.last]
        : [largest];
    for (final region in candidates) {
      // Keep spread planning stable as controls appear and disappear. A single
      // page with a bottom dock uses the full safe region below, with overlays.
      final right = !bottom && region == controls ? 140.0 : 0.0;
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
    return ReaderLayout(
      pageMode: canSpread ? ReaderPageMode.spread : ReaderPageMode.single,
      dockPlacement: bottom ? DockPlacement.bottom : DockPlacement.side,
      usableContentBounds: canSpread ? combined : single,
      pageRegions: List.unmodifiable(canSpread ? spreadRegions : [single]),
      controlsRegion: controls,
      safeRegions: List.unmodifiable(regions),
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
