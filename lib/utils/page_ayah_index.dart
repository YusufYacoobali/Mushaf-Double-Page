import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Maps each physical mushaf page to the ayahs printed on it, so translation /
/// tafseer can be shown page-by-page matching the printed Mushaf.
///
/// Backing data: `assets/arabic-text/*_page_map.json`
///   `{ "<logicalPage>": [[surah, firstAyah, lastAyah], ...], ... }`
/// generated separately for each printed layout. See the matching tools under
/// `tool/` and `tool/cv_work/` for provenance and validation.
///
/// Page numbering: the app's logical page is the printed page plus three cover
/// screens, i.e. `logicalPage = printedPage + [printedPageOffset]`. An ayah that
/// straddles a page break is listed on both pages (its words appear on both).
///
class PageAyahIndex {
  PageAyahIndex._();

  /// logicalPage -> list of `[surah, firstAyah, lastAyah]` segments.
  static final Map<String, Map<int, List<List<int>>>> _byMushaf = {};

  /// surah -> earliest logical page on which its ayah 1 appears.
  static final Map<String, Map<int, int>> _surahStartPage = {};

  /// (surah * 1000 + ayah) -> earliest logical page the ayah appears on.
  static final Map<String, Map<int, int>> _ayahPage = {};

  /// Logical page = printed mushaf page + this many cover screens.
  static const int printedPageOffset = 3;

  static bool get isReady =>
      _byMushaf.containsKey('indopak') && _byMushaf.containsKey('madani');

  static Future<void> load() async {
    if (isReady) return;
    if (!_byMushaf.containsKey('indopak')) {
      await _loadAsset('indopak', 'assets/arabic-text/indopak_page_map.json');
    }
    if (!_byMushaf.containsKey('madani')) {
      await _loadAsset('madani', 'assets/arabic-text/madani_page_map.json');
    }
  }

  static Future<void> _loadAsset(String mushaf, String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    final map = <int, List<List<int>>>{};
    final surahStart = <int, int>{};
    final ayahPage = <int, int>{};

    decoded.forEach((pageStr, segs) {
      final page = int.parse(pageStr);
      final segments = <List<int>>[];
      for (final s in segs as List) {
        final seg = [for (final e in s as List) e as int];
        segments.add(seg);
        // Record where each surah begins (its ayah-1 segment).
        if (seg[1] == 1) {
          final existing = surahStart[seg[0]];
          if (existing == null || page < existing) surahStart[seg[0]] = page;
        }
        // Record the earliest page each ayah appears on.
        for (var a = seg[1]; a <= seg[2]; a++) {
          final key = seg[0] * 1000 + a;
          final existing = ayahPage[key];
          if (existing == null || page < existing) ayahPage[key] = page;
        }
      }
      map[page] = segments;
    });

    _byMushaf[mushaf] = map;
    _surahStartPage[mushaf] = surahStart;
    _ayahPage[mushaf] = ayahPage;
  }

  static String _keyFor(String mushaf) =>
      mushaf == 'indopak_tajweed' ? 'indopak' : mushaf;

  /// Whether a page-level ayah map exists for this mushaf at all (regardless of
  /// a specific page). Used to choose page-based vs surah-based translation.
  static bool supportsMushaf(String mushaf) =>
      _byMushaf.containsKey(_keyFor(mushaf));

  /// Whether a page-level ayah map is available for [mushaf] and [logicalPage].
  static bool hasPage(String mushaf, int logicalPage) =>
      supportsMushaf(mushaf) &&
      (_byMushaf[_keyFor(mushaf)]?.containsKey(logicalPage) ?? false);

  /// Raw `[surah, firstAyah, lastAyah]` segments for a page, in reading order.
  static List<List<int>> segmentsForPage(
    int logicalPage, {
    String mushaf = 'indopak_tajweed',
  }) => _byMushaf[_keyFor(mushaf)]?[logicalPage] ?? const [];

  /// Flat list of every ayah on a page, in reading order.
  static List<({int surah, int ayah})> ayahsForPage(
    int logicalPage, {
    String mushaf = 'indopak_tajweed',
  }) => ayahsForPages([logicalPage], mushaf: mushaf);

  /// Merged `[surah, firstAyah, lastAyah]` segments across several pages (e.g. a
  /// landscape two-page spread), in reading order. An ayah that straddles a page
  /// break is collapsed into a single segment so it is not shown twice.
  static List<List<int>> segmentsForPages(
    Iterable<int> logicalPages, {
    String mushaf = 'indopak_tajweed',
  }) {
    final bySurah = <int, List<int>>{};
    final order = <int>[];
    for (final p in logicalPages) {
      for (final seg in segmentsForPage(p, mushaf: mushaf)) {
        final s = seg[0];
        final existing = bySurah[s];
        if (existing == null) {
          bySurah[s] = [seg[1], seg[2]];
          order.add(s);
        } else {
          if (seg[1] < existing[0]) existing[0] = seg[1];
          if (seg[2] > existing[1]) existing[1] = seg[2];
        }
      }
    }
    return [
      for (final s in order) [s, bySurah[s]![0], bySurah[s]![1]],
    ];
  }

  /// Flat list of every ayah across several pages, de-duplicated and in order.
  static List<({int surah, int ayah})> ayahsForPages(
    Iterable<int> logicalPages, {
    String mushaf = 'indopak_tajweed',
  }) {
    final out = <({int surah, int ayah})>[];
    for (final seg in segmentsForPages(logicalPages, mushaf: mushaf)) {
      for (var a = seg[1]; a <= seg[2]; a++) {
        out.add((surah: seg[0], ayah: a));
      }
    }
    return out;
  }

  /// Distinct surahs appearing on a page, in reading order.
  static List<int> surahsOnPage(
    int logicalPage, {
    String mushaf = 'indopak_tajweed',
  }) {
    final seen = <int>[];
    for (final seg in segmentsForPage(logicalPage, mushaf: mushaf)) {
      if (!seen.contains(seg[0])) seen.add(seg[0]);
    }
    return seen;
  }

  /// The logical page on which [surah] begins, or null if unknown.
  static int? pageForSurah(int surah, {String mushaf = 'indopak_tajweed'}) =>
      _surahStartPage[_keyFor(mushaf)]?[surah];

  /// The logical page a specific ayah appears on, or null if unknown.
  static int? pageOfAyah(
    int surah,
    int ayah, {
    String mushaf = 'indopak_tajweed',
  }) => _ayahPage[_keyFor(mushaf)]?[surah * 1000 + ayah];

  static int firstContentPageFor(String mushaf) {
    final map = _byMushaf[_keyFor(mushaf)];
    return map == null || map.isEmpty
        ? 4
        : map.keys.reduce((a, b) => a < b ? a : b);
  }

  static int lastContentPageFor(String mushaf) {
    final map = _byMushaf[_keyFor(mushaf)];
    return map == null || map.isEmpty
        ? 850
        : map.keys.reduce((a, b) => a > b ? a : b);
  }

  static int totalPrintedPagesFor(String mushaf) =>
      lastContentPageFor(mushaf) - firstContentPageFor(mushaf) + 1;

  static int get firstContentPage => firstContentPageFor('indopak');
  static int get lastContentPage => lastContentPageFor('indopak');
  static int get totalPrintedPages => totalPrintedPagesFor('indopak');

  /// The printed page number shown to the user (1-based in the Mushaf).
  static int printedPage(int logicalPage) => logicalPage - printedPageOffset;
}
