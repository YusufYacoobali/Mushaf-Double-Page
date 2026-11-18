import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/audio_page_follower.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PageAyahIndex.load);
  test('book audio follows actual odd-start pairs without parity snapping', () {
    final follower = AudioPageFollower();
    int? follow(int surah, int ayah) => follower.targetPage(
      playing: true,
      session: 1,
      cycle: 1,
      surah: surah,
      ayah: ayah,
      currentPage: 5,
      portrait: false,
      mushaf: 'indopak_tajweed',
      visiblePages: [5, 6],
      sequentialBook: true,
    );
    final visible = PageAyahIndex.ayahsForPage(
      6,
      mushaf: 'indopak_tajweed',
    ).last;
    expect(follow(visible.surah, visible.ayah), isNull);
    final next = PageAyahIndex.ayahsForPage(7, mushaf: 'indopak_tajweed').last;
    expect(
      follow(next.surah, next.ayah),
      PageAyahIndex.pageOfAyah(
        next.surah,
        next.ayah,
        mushaf: 'indopak_tajweed',
      ),
    );
  });
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
  test(
    'changing page mode cannot refollow the same playing ayah after a manual move',
    () {
      final follower = AudioPageFollower();
      int? follow(bool single, int ayah) => follower.targetPage(
        playing: true,
        session: 42,
        cycle: 1,
        surah: 2,
        ayah: ayah,
        currentPage: 237,
        portrait: single,
        mushaf: 'madani',
      );
      expect(follow(true, 1), isNotNull);
      expect(follow(false, 1), isNull);
      expect(follow(true, 1), isNull);
      expect(follow(false, 2), isNotNull);
    },
  );
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
  for (final mushaf in ['indopak_tajweed', 'madani']) {
    test(
      'covered reader consumes changes without a catch-up jump: $mushaf',
      () {
        final follower = AudioPageFollower();
        int? follow(int ayah, {bool visible = true, bool playing = true}) =>
            follower.targetPage(
              playing: playing,
              visible: visible,
              session: 1,
              cycle: 1,
              surah: 2,
              ayah: ayah,
              currentPage: 100,
              portrait: true,
              mushaf: mushaf,
            );
        follow(1);
        expect(follow(2, visible: false), isNull);
        expect(follow(2), isNull);
        expect(follow(2, playing: false), isNull);
        expect(follow(2), isNull);
        expect(follow(3), isNotNull);
      },
    );
  }
}
