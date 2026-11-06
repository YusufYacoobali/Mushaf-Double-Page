import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'page_ayah_index.dart';
import 'surah_mapper.dart';

class SurahVisit {
  const SurahVisit({required this.surah, required this.page});
  final int surah;
  final int page;
}

/// Keeps the last page in the current and previous surahs for quick switching.
class RecentSurahHistory {
  RecentSurahHistory(this.mushaf);
  final String mushaf;
  SurahVisit? current;
  SurahVisit? previous;
  Future<void> _pendingSave = Future.value();

  String get _key =>
      'recent_surahs_${mushaf == 'indopak_tajweed' ? 'indopak' : mushaf}';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      SurahVisit? decode(dynamic value) {
        if (value is! Map) return null;
        final surah = value['surah'];
        final page = value['page'];
        if (surah is! int || page is! int || surah < 1 || surah > 114) {
          return null;
        }
        final range = getSurahRanges(
          mushaf,
        ).firstWhere((s) => s.surah == surah);
        // A landscape spread can start one page before this surah.
        if (page < range.start - 1 || page > range.end) return null;
        return SurahVisit(surah: surah, page: page);
      }

      current = decode(data['current']);
      previous = decode(data['previous']);
      if (previous?.surah == current?.surah) previous = null;
    } on FormatException {
      // Ignore an invalid saved history; reading can start a fresh one.
    } on TypeError {
      // Ignore an obsolete history format.
    }
  }

  bool visit(int page, {int pagesPerView = 1, int? surah}) {
    final visible = <int>{};
    final surahsByPage = <int, Set<int>>{};
    for (var offset = 0; offset < pagesPerView; offset++) {
      final physicalPage = page + offset;
      final mapped = PageAyahIndex.surahsOnPage(physicalPage, mushaf: mushaf);
      final pageSurahs =
          (mapped.isNotEmpty
                  ? mapped
                  : surahsFromLogicalPage(
                      physicalPage,
                      mushaf,
                    ).where((s) => s.surah > 0).map((s) => s.surah))
              .toSet();
      surahsByPage[physicalPage] = pageSurahs;
      visible.addAll(pageSurahs);
    }
    if (visible.isEmpty) return false;
    final active = surah != null && visible.contains(surah)
        ? surah
        : visible.contains(current?.surah)
        ? current!.surah
        : visible.first;
    // Store the physical page containing the chosen surah, so returning in
    // portrait doesn't open the preceding surah from the other half of a spread.
    final readingPage = surahsByPage.entries
        .firstWhere((entry) => entry.value.contains(active))
        .key;
    if (current?.surah == active && current?.page == readingPage) return false;
    if (current != null && current!.surah != active) previous = current;
    current = SurahVisit(surah: active, page: readingPage);
    return true;
  }

  Future<void> save() {
    Map<String, int>? encode(SurahVisit? visit) =>
        visit == null ? null : {'surah': visit.surah, 'page': visit.page};
    final snapshot = jsonEncode({
      'current': encode(current),
      'previous': encode(previous),
    });
    return _pendingSave = _pendingSave.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, snapshot);
    });
  }
}
