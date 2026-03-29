import '../utils/surah_mapper.dart';

class Bookmark {
  final int pageNumber;
  final String mushaf;
  String? surah;

  Bookmark({
    required this.pageNumber,
    required this.mushaf,
    String? surah,
  }) : surah = surah ?? surahNameFromPage(pageNumber, mushaf);

  Map<String, dynamic> toMap() => {
    'pageNumber': pageNumber,
    'surah': surah,
    'mushaf': mushaf,
  };

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      pageNumber: map['pageNumber'],
      mushaf: map['mushaf'] ?? "indopak_tajweed",
      surah: map['surah'],
    );
  }
}