import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('portrait and landscape page scales are stored independently', () async {
    await StorageManager.savePageScalePortrait(0.75);
    await StorageManager.savePageScaleLandscape(0.9);

    expect(await StorageManager.getPageScalePortrait(), 0.75);
    expect(await StorageManager.getPageScaleLandscape(), 0.9);
  });

  test('ayah highlighting is enabled by default and persists', () async {
    expect(await StorageManager.getAyahHighlightingEnabled(), true);

    await StorageManager.saveAyahHighlightingEnabled(false);
    expect(await StorageManager.getAyahHighlightingEnabled(), false);

    await StorageManager.saveAyahHighlightingEnabled(true);
    expect(await StorageManager.getAyahHighlightingEnabled(), true);
  });

  test(
    'removing the final bookmark clears only the active mushaf bookmarks',
    () async {
      await StorageManager.saveBookmarks([
        Bookmark(pageNumber: 10, mushaf: 'indopak_tajweed'),
        Bookmark(pageNumber: 20, mushaf: 'madani'),
      ]);

      await StorageManager.saveBookmarks([], mushaf: 'madani');

      final indopak = await StorageManager.getBookmarks('indopak_tajweed');
      final madani = await StorageManager.getBookmarks('madani');

      expect(indopak.map((bookmark) => bookmark.pageNumber), [10]);
      expect(madani, isEmpty);
    },
  );

  test('mushaf aliases resolve to the correct surah ranges', () {
    expect(getSurahRanges('indopak_tajweed'), same(getSurahRanges('indopak')));
    expect(getSurahRanges('madani'), same(madaniSurahRanges));
  });

  test('mushaf conversion clamps within valid file-backed page ranges', () {
    expect(PageMapper.indoPakToMadani(0), 1);
    expect(
      PageMapper.indoPakToMadani(PageMapper.indopakLastFilePage),
      PageMapper.madaniLastFilePage,
    );
    expect(
      PageMapper.madaniToIndoPak(PageMapper.madaniLastFilePage),
      PageMapper.indopakLastFilePage,
    );
  });
}
