import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/juz_mapper.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all four printed quarter destinations in every edition', () async {
    await PageAyahIndex.load();
    final printed = {
      'madani': [
        1,
        7,
        11,
        17,
        22,
        27,
        32,
        37,
        42,
        46,
        51,
        56,
        62,
        67,
        72,
        77,
        82,
        87,
        92,
        97,
        102,
        106,
        112,
        117,
        121,
        126,
        132,
        137,
        142,
        146,
        151,
        156,
        162,
        167,
        173,
        177,
        182,
        187,
        192,
        196,
        201,
        206,
        212,
        217,
        222,
        226,
        231,
        236,
        242,
        247,
        252,
        256,
        262,
        267,
        272,
        277,
        282,
        287,
        292,
        297,
        302,
        306,
        312,
        317,
        322,
        326,
        332,
        336,
        342,
        347,
        352,
        356,
        362,
        367,
        371,
        377,
        382,
        386,
        392,
        396,
        402,
        407,
        413,
        418,
        422,
        426,
        431,
        436,
        442,
        446,
        451,
        456,
        462,
        467,
        472,
        477,
        482,
        486,
        491,
        496,
        502,
        507,
        513,
        517,
        522,
        526,
        531,
        536,
        542,
        547,
        553,
        558,
        562,
        566,
        572,
        577,
        582,
        587,
        591,
        596,
      ],
      'indopak': [
        1,
        9,
        15,
        21,
        28,
        34,
        41,
        49,
        56,
        62,
        70,
        77,
        84,
        90,
        98,
        104,
        112,
        119,
        125,
        133,
        140,
        147,
        154,
        161,
        168,
        175,
        182,
        189,
        196,
        201,
        208,
        215,
        224,
        230,
        237,
        245,
        252,
        259,
        266,
        272,
        280,
        286,
        294,
        300,
        308,
        314,
        321,
        329,
        336,
        342,
        350,
        356,
        364,
        370,
        377,
        384,
        392,
        398,
        405,
        412,
        420,
        426,
        434,
        440,
        448,
        454,
        461,
        468,
        476,
        482,
        489,
        496,
        504,
        510,
        517,
        524,
        532,
        537,
        544,
        551,
        558,
        565,
        572,
        580,
        586,
        592,
        598,
        605,
        612,
        619,
        625,
        632,
        640,
        646,
        652,
        659,
        666,
        673,
        679,
        687,
        696,
        703,
        712,
        717,
        726,
        733,
        740,
        747,
        756,
        763,
        769,
        777,
        786,
        793,
        802,
        810,
        818,
        825,
        832,
        839,
      ],
    };
    for (final edition in ['madani', 'indopak', 'indopak_tajweed']) {
      final expected = printed[edition == 'madani' ? edition : 'indopak']!;
      expect(expected.length, 120);
      for (var i = 0; i < expected.length; i++) {
        final juz = 1 + i ~/ 4, quarter = 1 + i % 4;
        final dest = juzDestination(juz, quarter, edition);
        expect(
          PageAyahIndex.printedPage(dest.page),
          expected[i],
          reason: '$edition $juz/$quarter',
        );
        if (quarter == 1) expect(pageFromJuz(juz, edition), dest.page);
      }
    }
  });

  test(
    'Indo-Pak marginal signs shared by multiple verses have one destination',
    () async {
      await PageAyahIndex.load();
      for (final edition in ['indopak', 'indopak_tajweed']) {
        for (final (juz, surah, first, last) in [
          (23, 38, 53, 54),
          (25, 44, 22, 24),
        ]) {
          final destination = juzDestination(juz, 4, edition);
          for (var ayah = first; ayah <= last; ayah++) {
            expect(
              PageAyahIndex.pageOfAyah(surah, ayah, mushaf: edition),
              destination.page,
            );
          }
        }
      }
    },
  );

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
