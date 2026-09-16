import 'page_ayah_index.dart';
import 'page_mapper.dart';

/// Follow new playback verses without snapping back on unrelated player updates.
class AudioPageFollower {
  String? _lastVerse;

  int? targetPage({
    required bool playing,
    required int session,
    required int? cycle,
    required int? surah,
    required int? ayah,
    required int currentPage,
    required bool portrait,
    required String mushaf,
  }) {
    if (!playing || surah == null || ayah == null) {
      _lastVerse = null;
      return null;
    }
    final identity = '$session:$cycle:$surah:$ayah:$portrait:$mushaf';
    if (identity == _lastVerse) return null;
    final target = PageAyahIndex.pageOfAyah(surah, ayah, mushaf: mushaf);
    if (target == null) return null;
    _lastVerse = identity;
    final firstVisible = portrait ? currentPage : (currentPage ~/ 2) * 2;
    // An ayah can straddle pages. Keep the visible portion instead of jumping
    // backwards to its first page, including the other half of a spread.
    for (var p = firstVisible; p < firstVisible + (portrait ? 1 : 2); p++) {
      for (final segment in PageAyahIndex.segmentsForPage(p, mushaf: mushaf)) {
        if (segment[0] == surah && ayah >= segment[1] && ayah <= segment[2]) {
          return null;
        }
      }
    }
    return PageMapper.logicalFromPageIndex(
      PageMapper.pageIndexFromLogical(target, portrait),
      portrait,
    );
  }
}
