import '../utils/surah_mapper.dart';

class Bookmark {
  final int pageNumber;
  String? surah;

  Bookmark({
    required this.pageNumber,
    String? surah,
  }) : surah = surah ?? surahNameFromPage(pageNumber);

  // Serialize Bookmark object to a Map
  Map<String, dynamic> toMap() => {
    'pageNumber': pageNumber,
    'surah': surah,
  };

  // Deserialize Map to a Bookmark object
  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      pageNumber: map['pageNumber'],
      surah: map['surah'],
    );
  }
}