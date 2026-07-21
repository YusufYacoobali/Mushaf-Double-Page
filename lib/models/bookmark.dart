import '../utils/surah_mapper.dart';

/// A saved location. Two kinds:
///  - page bookmark: [ayah] is null; identified by [pageNumber].
///  - ayah bookmark: [surahNumber] and [ayah] are set; [pageNumber] is the page
///    the ayah appears on (used for navigation).
class Bookmark {
  final int pageNumber;
  final String mushaf;
  final int? surahNumber;
  final int? ayah;
  final String? surah; // display name

  Bookmark({
    required this.pageNumber,
    required this.mushaf,
    this.surahNumber,
    this.ayah,
    String? surah,
  }) : surah =
           surah ??
           (surahNumber != null
               ? surahNameFromNumber(surahNumber, mushaf)
               : surahNameFromPage(pageNumber, mushaf));

  bool get isAyah => ayah != null;

  /// Identity used for de-duplication and removal: ayah bookmarks match on
  /// surah+ayah, page bookmarks match on page.
  bool sameAs(Bookmark other) => isAyah
      ? (other.isAyah &&
            other.surahNumber == surahNumber &&
            other.ayah == ayah)
      : (!other.isAyah && other.pageNumber == pageNumber);

  Map<String, dynamic> toMap() => {
    'pageNumber': pageNumber,
    'surah': surah,
    'mushaf': mushaf,
    if (surahNumber != null) 'surahNumber': surahNumber,
    if (ayah != null) 'ayah': ayah,
  };

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      pageNumber: map['pageNumber'],
      mushaf: map['mushaf'] ?? "indopak_tajweed",
      surahNumber: map['surahNumber'],
      ayah: map['ayah'],
      surah: map['surah'],
    );
  }
}
