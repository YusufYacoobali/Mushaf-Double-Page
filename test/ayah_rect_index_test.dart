import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/ayah_rect_index.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AyahRectIndex loads and hit-tests ayah regions', () async {
    await AyahRectIndex.load();

    expect(AyahRectIndex.isReady, true);
    expect(AyahRectIndex.supportsMushaf('indopak_tajweed'), true);
    expect(AyahRectIndex.supportsMushaf('madani'), true);

    final regions = AyahRectIndex.forPage(5); // Al-Baqarah 2:1-4
    expect(regions, isNotEmpty);

    final first = regions.first;
    expect(first.rects, isNotEmpty);

    // The centre of a region's rectangle hit-tests to that ayah.
    final r = first.rects.first;
    final cx = (r.left + r.right) / 2;
    final cy = (r.top + r.bottom) / 2;
    final hit = AyahRectIndex.hitTest(5, cx, cy);
    expect(hit, isNotNull);
    expect(hit!.surah, first.surah);
    expect(hit.ayah, first.ayah);

    // A finger just above the tightly traced ink still resolves to the ayah.
    final nearTopEdge = AyahRectIndex.hitTest(5, cx, r.top - (5 / 1058));
    expect(nearTopEdge, isNotNull);
    expect(nearTopEdge!.surah, first.surah);
    expect(nearTopEdge.ayah, first.ayah);

    // Immediately left of this ending circle is the next ayah in RTL reading
    // order. It must not be swallowed by the previous highlight/hit region.
    final afterEndingCircle = AyahRectIndex.hitTest(5, r.left - (5 / 721), cy);
    expect(afterEndingCircle, isNotNull);
    expect(afterEndingCircle!.ayah, isNot(first.ayah));

    expect(AyahRectIndex.rectsFor(5, first.surah, first.ayah), isNotEmpty);

    // A point off the page hits nothing.
    expect(AyahRectIndex.hitTest(5, -0.5, -0.5), isNull);

    // Every rect is within the normalised page bounds.
    for (final region in regions) {
      for (final rect in region.rects) {
        expect(rect.left >= 0 && rect.right <= 1, true);
        expect(rect.top >= 0 && rect.bottom <= 1, true);
      }
    }
  });

  test('Madani regions use the same precise hit-test path', () async {
    await AyahRectIndex.load();

    final regions = AyahRectIndex.forPage(6, mushaf: 'madani');
    expect(regions, isNotEmpty);
    final region = regions.first;
    final rect = region.rects.first;
    final hit = AyahRectIndex.hitTest(
      6,
      (rect.left + rect.right) / 2,
      (rect.top + rect.bottom) / 2,
      mushaf: 'madani',
    );
    expect(hit, (surah: region.surah, ayah: region.ayah));
  });

  test(
    'an ayah crossing a page break has highlight regions on both pages',
    () async {
      await AyahRectIndex.load();

      // Al-Ma'un 105:2 begins on logical page 846 and finishes on 847.
      expect(AyahRectIndex.rectsFor(846, 105, 2), isNotEmpty);
      expect(AyahRectIndex.rectsFor(847, 105, 2), isNotEmpty);
    },
  );

  test('AyahRectIndex covers every Indo-Pak page-mapped ayah', () async {
    await PageAyahIndex.load();
    await AyahRectIndex.load();

    var ayahCount = 0;
    for (
      var page = PageAyahIndex.firstContentPage;
      page <= PageAyahIndex.lastContentPage;
      page++
    ) {
      for (final ayah in PageAyahIndex.ayahsForPage(page)) {
        ayahCount++;
        final rects = AyahRectIndex.rectsFor(page, ayah.surah, ayah.ayah);
        expect(
          rects,
          isNotEmpty,
          reason: 'Missing rects for ${ayah.surah}:${ayah.ayah} on page $page',
        );

        for (final rect in rects) {
          expect(rect.width > 0, true);
          expect(rect.height > 0, true);
          expect(rect.left >= 0 && rect.right <= 1, true);
          expect(rect.top >= 0 && rect.bottom <= 1, true);
        }
      }
    }

    expect(ayahCount, greaterThan(6200));
  });

  test('AyahRectIndex covers every Madani page-mapped ayah', () async {
    await PageAyahIndex.load();
    await AyahRectIndex.load();

    var ayahCount = 0;
    for (var page = 4; page <= 607; page++) {
      for (final ayah in PageAyahIndex.ayahsForPage(page, mushaf: 'madani')) {
        ayahCount++;
        final rects = AyahRectIndex.rectsFor(
          page,
          ayah.surah,
          ayah.ayah,
          mushaf: 'madani',
        );
        expect(
          rects,
          isNotEmpty,
          reason:
              'Missing Madani rects for ${ayah.surah}:${ayah.ayah} on $page',
        );
        for (final rect in rects) {
          expect(rect.width, greaterThan(0));
          expect(rect.height, greaterThan(0));
          expect(rect.left >= 0 && rect.right <= 1, true);
          expect(rect.top >= 0 && rect.bottom <= 1, true);
        }
      }
    }
    expect(ayahCount, 6236);
  });

  test('different ayahs never paint over one another', () async {
    await AyahRectIndex.load();

    for (final (mushaf, lastPage) in [
      ('indopak_tajweed', 850),
      ('madani', 607),
    ]) {
      for (var page = 4; page <= lastPage; page++) {
        final regions = AyahRectIndex.forPage(page, mushaf: mushaf);
        for (var first = 0; first < regions.length; first++) {
          for (var second = first + 1; second < regions.length; second++) {
            for (final a in regions[first].rects) {
              for (final b in regions[second].rects) {
                final overlap = a.intersect(b);
                expect(
                  overlap.width <= 0 || overlap.height <= 0,
                  true,
                  reason:
                      'Overlapping $mushaf ayahs on page $page: '
                      '${regions[first].surah}:${regions[first].ayah} and '
                      '${regions[second].surah}:${regions[second].ayah}',
                );
              }
            }
          }
        }
      }
    }
  });

  test('special opening pages stay inside their Quran text frame', () async {
    await AyahRectIndex.load();

    for (final page in [4, 5]) {
      for (final region in AyahRectIndex.forPage(page)) {
        for (final rect in region.rects) {
          expect(rect.left, greaterThanOrEqualTo(85 / 721));
          expect(rect.right, lessThanOrEqualTo(635 / 721));
        }
      }
    }

    for (final region in AyahRectIndex.forPage(4, mushaf: 'madani')) {
      for (final rect in region.rects) {
        expect(rect.left, greaterThanOrEqualTo(200 / 2096));
        expect(rect.right, lessThanOrEqualTo(1500 / 2096));
      }
    }
    for (final region in AyahRectIndex.forPage(5, mushaf: 'madani')) {
      for (final rect in region.rects) {
        expect(rect.left, greaterThanOrEqualTo(570 / 2096));
        expect(rect.right, lessThanOrEqualTo(1900 / 2096));
      }
    }
  });
}
