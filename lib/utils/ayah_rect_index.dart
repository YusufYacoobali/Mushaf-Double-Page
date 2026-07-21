import 'dart:convert';
import 'dart:ui' show Offset, Rect;
import 'package:flutter/services.dart' show rootBundle;

/// A single ayah's highlight regions on a page, as rectangles in normalised
/// page coordinates (0..1 of the page image, left/top/right/bottom).
class AyahRegion {
  final int surah;
  final int ayah;
  final List<Rect> rects;
  const AyahRegion(this.surah, this.ayah, this.rects);
}

/// Per-page ayah hit-test regions and highlight rectangles, derived separately
/// from each supported printed mushaf (see tool/cv_work).
class AyahRectIndex {
  AyahRectIndex._();

  static final Map<String, Map<int, List<AyahRegion>>> _byMushaf = {};

  static bool get isReady =>
      _byMushaf.containsKey('indopak') && _byMushaf.containsKey('madani');

  static Future<void> load() async {
    if (isReady) return;
    _byMushaf['indopak'] ??= await _loadAsset(
      'assets/arabic-text/indopak_ayah_rects.json',
    );
    _byMushaf['madani'] ??= await _loadAsset(
      'assets/arabic-text/madani_ayah_rects.json',
    );
  }

  static Future<Map<int, List<AyahRegion>>> _loadAsset(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final map = <int, List<AyahRegion>>{};
    decoded.forEach((pageStr, rows) {
      final regions = <AyahRegion>[];
      for (final row in rows as List) {
        final r = (row as List).cast<num>();
        final surah = r[0].toInt();
        final ayah = r[1].toInt();
        final rects = <Rect>[];
        for (var i = 2; i + 3 < r.length; i += 4) {
          rects.add(
            Rect.fromLTRB(
              r[i] / 1000,
              r[i + 1] / 1000,
              r[i + 2] / 1000,
              r[i + 3] / 1000,
            ),
          );
        }
        regions.add(AyahRegion(surah, ayah, rects));
      }
      map[int.parse(pageStr)] = regions;
    });
    return map;
  }

  static String _keyFor(String mushaf) =>
      mushaf == 'indopak_tajweed' ? 'indopak' : mushaf;

  static bool supportsMushaf(String mushaf) =>
      _byMushaf.containsKey(_keyFor(mushaf));

  static List<AyahRegion> forPage(
    int logicalPage, {
    String mushaf = 'indopak_tajweed',
  }) => _byMushaf[_keyFor(mushaf)]?[logicalPage] ?? const [];

  /// The ayah whose region contains the normalised point (nx, ny), or null.
  static ({int surah, int ayah})? hitTest(
    int logicalPage,
    double nx,
    double ny, {
    String mushaf = 'indopak_tajweed',
  }) {
    final point = Offset(nx, ny);
    ({int surah, int ayah, double area})? best;

    for (final region in forPage(logicalPage, mushaf: mushaf)) {
      for (final rect in region.rects) {
        if (rect.contains(point)) {
          final area = rect.width * rect.height;
          if (best == null || area < best.area) {
            best = (surah: region.surah, ayah: region.ayah, area: area);
          }
        }
      }
    }

    if (best != null) return (surah: best.surah, ayah: best.ayah);

    // The geometry follows the visible ink closely. Give fingers a small,
    // page-relative margin so a tap on a vowel mark or in the narrow gap
    // between connected glyphs still selects the intended ayah. Exact hits
    // above always win; for a near hit, choose the closest rectangle.
    final horizontalSlop = mushaf == 'madani' ? 25 / 2096 : 10 / 721;
    final verticalSlop = mushaf == 'madani' ? 34 / 3008 : 12 / 1058;
    final sourceWidth = mushaf == 'madani' ? 2096.0 : 721.0;
    final sourceHeight = mushaf == 'madani' ? 3008.0 : 1058.0;
    ({int surah, int ayah, double distance})? nearest;
    for (final region in forPage(logicalPage, mushaf: mushaf)) {
      for (final rect in region.rects) {
        final dx = nx < rect.left
            ? rect.left - nx
            : nx > rect.right
            ? nx - rect.right
            : 0.0;
        final dy = ny < rect.top
            ? rect.top - ny
            : ny > rect.bottom
            ? ny - rect.bottom
            : 0.0;
        if (dx > horizontalSlop || dy > verticalSlop) continue;

        // Compare in source-image pixels so x/y distances have equal weight.
        final distance =
            (dx * sourceWidth) * (dx * sourceWidth) +
            (dy * sourceHeight) * (dy * sourceHeight);
        if (nearest == null || distance < nearest.distance) {
          nearest = (
            surah: region.surah,
            ayah: region.ayah,
            distance: distance,
          );
        }
      }
    }

    if (nearest == null) return null;
    return (surah: nearest.surah, ayah: nearest.ayah);
  }

  /// Highlight rectangles (normalised) for a specific ayah on a page.
  static List<Rect> rectsFor(
    int logicalPage,
    int surah,
    int ayah, {
    String mushaf = 'indopak_tajweed',
  }) {
    for (final region in forPage(logicalPage, mushaf: mushaf)) {
      if (region.surah == surah && region.ayah == ayah) return region.rects;
    }
    return const [];
  }
}
