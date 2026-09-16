import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/audio_page_follower.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PageAyahIndex.load);
  for (final mushaf in ['indopak_tajweed', 'madani']) {
    for (final portrait in [true, false]) {
      test(
        'follows page boundaries and repeat restarts: $mushaf portrait=$portrait',
        () {
          final follower = AudioPageFollower();
          int? follow(
            int surah,
            int ayah,
            int page, {
            int cycle = 1,
            bool playing = true,
          }) => follower.targetPage(
            playing: playing,
            session: 1,
            cycle: cycle,
            surah: surah,
            ayah: ayah,
            currentPage: page,
            portrait: portrait,
            mushaf: mushaf,
          );
          expect(follow(1, 1, 4), isNull);
          // 2:1 is on page 5, already visible in the landscape 4/5 spread.
          expect(follow(2, 1, 4), portrait ? 5 : isNull);
          final next = PageAyahIndex.ayahsForPage(6, mushaf: mushaf).last;
          final page = PageAyahIndex.pageOfAyah(
            next.surah,
            next.ayah,
            mushaf: mushaf,
          )!;
          final expected = PageMapper.logicalFromPageIndex(
            PageMapper.pageIndexFromLogical(page, portrait),
            portrait,
          );
          expect(follow(next.surah, next.ayah, 4), expected);
          // Unrelated notifications must not fight a manual page swipe.
          expect(follow(next.surah, next.ayah, 20), isNull);
          expect(follow(1, 1, expected, cycle: 2), 4);
          expect(follow(next.surah, next.ayah, 4, playing: false), isNull);
          expect(follow(next.surah, next.ayah, 4), expected);
        },
      );
    }
  }
  test('keeps the visible part of a straddling ayah', () {
    final follower = AudioPageFollower();
    expect(
      follower.targetPage(
        playing: true,
        session: 1,
        cycle: 1,
        surah: 105,
        ayah: 2,
        currentPage: 847,
        portrait: true,
        mushaf: 'indopak_tajweed',
      ),
      isNull,
    );
    expect(
      follower.targetPage(
        playing: true,
        session: 1,
        cycle: 1,
        surah: 2,
        ayah: 9999,
        currentPage: 847,
        portrait: true,
        mushaf: 'indopak_tajweed',
      ),
      isNull,
    );
  });
}
