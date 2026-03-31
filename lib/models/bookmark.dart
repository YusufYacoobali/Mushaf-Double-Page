import '../utils/surah_mapper.dart';

class Bookmark {
  final int pageNumber;
  final String mushaf;
  String? surah;

  Bookmark({
    required this.pageNumber,
    required this.mushaf,
    String? surah,
  }) : surah = surahNameFromPage(pageNumber, mushaf)
  {print("Bookmark mushaf=$mushaf page=$pageNumber surah=$surah");}


  Map<String, dynamic> toMap() => {
    'pageNumber': pageNumber,
    'surah': surah,
    'mushaf': mushaf,
  };

  // factory Bookmark.fromMap(Map<String, dynamic> map) {
  //   return Bookmark(
  //     pageNumber: map['pageNumber'],
  //     mushaf: map['mushaf'] ?? "indopak_tajweed",
  //     surah: surahNameFromPage(page, mushaf),
  //   );
  // }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    final mushaf = map['mushaf'] ?? "indopak_tajweed";
    final page = map['pageNumber'];

    return Bookmark(
      pageNumber: page,
      mushaf: mushaf,
      surah: surahNameFromPage(page, mushaf),
    );
  }
}