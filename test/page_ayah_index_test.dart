import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PageAyahIndex loads the Indo-Pak layout and maps pages', () async {
    await PageAyahIndex.load();

    expect(PageAyahIndex.isReady, true);
    expect(PageAyahIndex.supportsMushaf('indopak_tajweed'), true);
    expect(PageAyahIndex.supportsMushaf('indopak'), true);
    expect(PageAyahIndex.supportsMushaf('madani'), true);

    // Page bounds (logical pages; 3 cover screens before Al-Fatiha).
    expect(PageAyahIndex.firstContentPage, 4);
    expect(PageAyahIndex.lastContentPage, 850);
    expect(PageAyahIndex.totalPrintedPages, 847);
    expect(PageAyahIndex.printedPage(4), 1);

    // Page 4 == Al-Fatiha 1:1–1:7.
    expect(PageAyahIndex.segmentsForPage(4), [
      [1, 1, 7],
    ]);

    // Page 70 spans the tail of Al-Baqarah and the start of Aal-E-Imran.
    expect(PageAyahIndex.surahsOnPage(70), [2, 3]);
    final ayahs = PageAyahIndex.ayahsForPage(70);
    expect(ayahs.first, (surah: 2, ayah: 286));
    expect(ayahs.last, (surah: 3, ayah: 7));

    // Surah jump targets resolve to the page where the surah begins.
    expect(PageAyahIndex.pageForSurah(2), 5); // Al-Baqarah
    expect(PageAyahIndex.pageForSurah(114), 850); // An-Nas

    // Reverse lookup: the page a specific ayah appears on (earliest, for
    // ayahs that straddle a break).
    expect(PageAyahIndex.pageOfAyah(1, 1), 4);
    expect(PageAyahIndex.pageOfAyah(2, 1), 5);
    expect(PageAyahIndex.pageOfAyah(114, 6), 850);
    expect(PageAyahIndex.pageOfAyah(105, 2), 846); // straddles 846/847
    expect(PageAyahIndex.pageOfAyah(2, 9999), isNull);

    // Unknown page yields no segments (e.g. a cover screen).
    expect(PageAyahIndex.segmentsForPage(1), isEmpty);
    expect(PageAyahIndex.hasPage('indopak_tajweed', 1), false);
    expect(PageAyahIndex.hasPage('indopak_tajweed', 4), true);
  });

  test(
    'PageAyahIndex maps the 604 printed Madani pages independently',
    () async {
      await PageAyahIndex.load();

      expect(PageAyahIndex.firstContentPageFor('madani'), 4);
      expect(PageAyahIndex.lastContentPageFor('madani'), 607);
      expect(PageAyahIndex.totalPrintedPagesFor('madani'), 604);
      expect(PageAyahIndex.hasPage('madani', 4), true);
      expect(PageAyahIndex.hasPage('madani', 608), false);

      expect(PageAyahIndex.segmentsForPage(4, mushaf: 'madani'), [
        [1, 1, 7],
      ]);
      expect(PageAyahIndex.segmentsForPage(5, mushaf: 'madani'), [
        [2, 1, 5],
      ]);
      // These late-page checks guard the visually verified joined 75:12
      // medallion and the following surah transition from sequence drift.
      expect(PageAyahIndex.segmentsForPage(580, mushaf: 'madani'), [
        [74, 48, 56],
        [75, 1, 19],
      ]);
      expect(PageAyahIndex.segmentsForPage(589, mushaf: 'madani'), [
        [80, 41, 42],
        [81, 1, 29],
      ]);
      expect(PageAyahIndex.segmentsForPage(607, mushaf: 'madani'), [
        [112, 1, 4],
        [113, 1, 5],
        [114, 1, 6],
      ]);

      expect(PageAyahIndex.pageForSurah(114, mushaf: 'madani'), 607);
      expect(PageAyahIndex.pageOfAyah(2, 1, mushaf: 'madani'), 5);
      expect(PageAyahIndex.pageOfAyah(114, 6, mushaf: 'madani'), 607);
    },
  );

  test(
    'landscape spread merges pages without duplicating a straddling ayah',
    () async {
      await PageAyahIndex.load();

      // Pages 846 and 847 both contain ayah 105:2 (it straddles the break):
      //   846 -> [[103,1,3],[104,1,9],[105,1,2]]
      //   847 -> [[105,2,5],[106,1,4],[107,1,7]]
      expect(PageAyahIndex.segmentsForPage(846), [
        [103, 1, 3],
        [104, 1, 9],
        [105, 1, 2],
      ]);
      expect(PageAyahIndex.segmentsForPages([846, 847]), [
        [103, 1, 3],
        [104, 1, 9],
        [105, 1, 5], // 105:2 collapsed into one segment
        [106, 1, 4],
        [107, 1, 7],
      ]);

      // 105:2 appears exactly once across the spread.
      final ayahs = PageAyahIndex.ayahsForPages([846, 847]);
      final straddler = ayahs
          .where((a) => a.surah == 105 && a.ayah == 2)
          .length;
      expect(straddler, 1);
    },
  );
}
