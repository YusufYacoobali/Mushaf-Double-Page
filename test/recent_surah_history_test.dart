import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/recent_surah_history.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(PageAyahIndex.load);

  for (final mushaf in ['indopak_tajweed', 'madani']) {
    test(
      'switching surahs preserves both reading positions in $mushaf',
      () async {
        final history = RecentSurahHistory(mushaf);
        final revision = pageFromSurah(2, mushaf) + 10;
        final memorisation = pageFromSurah(52, mushaf) + 1;
        history.visit(revision);
        history.visit(revision + 1);
        expect(history.previous, isNull);
        history.visit(memorisation, surah: 52);
        expect(history.previous!.surah, 2);
        expect(history.previous!.page, revision + 1);
        history.visit(memorisation + 1, surah: 52);
        final back = history.previous!;
        history.visit(back.page, surah: back.surah);
        expect(history.current!.surah, 2);
        expect(history.current!.page, revision + 1);
        expect(history.previous!.surah, 52);
        expect(history.previous!.page, memorisation + 1);
        await history.save();
        final restored = RecentSurahHistory(mushaf);
        await restored.load();
        expect(restored.current!.page, revision + 1);
        expect(restored.previous!.page, memorisation + 1);
        final again = restored.previous!;
        restored.visit(again.page, surah: again.surah);
        expect(restored.current!.surah, 52);
        expect(restored.previous!.surah, 2);
      },
    );

    test('shared pages and landscape keep the chosen surah in $mushaf', () {
      final history = RecentSurahHistory(mushaf);
      final target = PageAyahIndex.pageOfAyah(112, 1, mushaf: mushaf)!;
      final spread = target.isOdd ? target - 1 : target;
      history.visit(pageFromSurah(2, mushaf) + 10);
      history.visit(spread, pagesPerView: 2, surah: 112);
      expect(history.current!.surah, 112);
      expect(
        PageAyahIndex.surahsOnPage(history.current!.page, mushaf: mushaf),
        contains(112),
      );
      history.visit(spread, pagesPerView: 2);
      expect(history.current!.surah, 112);
      expect(history.previous!.surah, 2);
      history.visit(1);
      expect(history.current!.surah, 112);
      expect(history.previous!.surah, 2);
    });
  }

  test(
    'history is separate for each mushaf and Indo-Pak aliases share it',
    () async {
      final history = RecentSurahHistory('indopak_tajweed');
      history.visit(20);
      history.visit(pageFromSurah(52, 'indopak_tajweed') + 1, surah: 52);
      await history.save();
      final alias = RecentSurahHistory('indopak');
      await alias.load();
      expect(alias.current!.surah, 52);
      expect(alias.previous!.surah, 2);
      final madani = RecentSurahHistory('madani');
      await madani.load();
      expect(madani.current, isNull);
      expect(madani.previous, isNull);
    },
  );

  test('invalid stored history is ignored', () async {
    for (final value in [
      'invalid json',
      '{"current":{"surah":999,"page":8}}',
    ]) {
      SharedPreferences.setMockInitialValues({'recent_surahs_indopak': value});
      final history = RecentSurahHistory('indopak_tajweed');
      await history.load();
      expect(history.current, isNull);
      expect(history.previous, isNull);
    }
  });
}
