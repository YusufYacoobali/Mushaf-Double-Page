import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/models/bookmark.dart';

void main() {
  test('page bookmark round-trips and is identified by page', () {
    final b = Bookmark(pageNumber: 70, mushaf: 'indopak_tajweed');
    expect(b.isAyah, false);

    final restored = Bookmark.fromMap(b.toMap());
    expect(restored.pageNumber, 70);
    expect(restored.isAyah, false);
    expect(restored.surah, isNotNull);

    expect(
      b.sameAs(Bookmark(pageNumber: 70, mushaf: 'indopak_tajweed')),
      true,
    );
    expect(
      b.sameAs(Bookmark(pageNumber: 71, mushaf: 'indopak_tajweed')),
      false,
    );
  });

  test('ayah bookmark round-trips and is identified by surah:ayah', () {
    final b = Bookmark(
      pageNumber: 42,
      mushaf: 'indopak_tajweed',
      surahNumber: 2,
      ayah: 255,
    );
    expect(b.isAyah, true);
    expect(b.surah, 'Al-Baqarah');

    final restored = Bookmark.fromMap(b.toMap());
    expect(restored.isAyah, true);
    expect(restored.surahNumber, 2);
    expect(restored.ayah, 255);
    expect(restored.pageNumber, 42);

    // Identity ignores the page for ayah bookmarks.
    expect(
      b.sameAs(
        Bookmark(
          pageNumber: 999,
          mushaf: 'indopak_tajweed',
          surahNumber: 2,
          ayah: 255,
        ),
      ),
      true,
    );
    expect(
      b.sameAs(
        Bookmark(
          pageNumber: 42,
          mushaf: 'indopak_tajweed',
          surahNumber: 2,
          ayah: 256,
        ),
      ),
      false,
    );
    // An ayah bookmark never matches a page bookmark.
    expect(
      b.sameAs(Bookmark(pageNumber: 42, mushaf: 'indopak_tajweed')),
      false,
    );
  });
}
