import '../utils/surah_mapper.dart';

class Bookmark {
  final int pageNumber;
  String? surah;

  /// Creates a Bookmark instance
  /// Surah uses mapper to get value from page number
  Bookmark({
    required this.pageNumber,
    String? surah,
  }) : surah = surah ?? surahNameFromPage(pageNumber);

  /// Converts this Bookmark into a Map, Serializes it
  /// Used for local storage (e.g. SharedPreferences, JSON)
  Map<String, dynamic> toMap() => {
    'pageNumber': pageNumber,
    'surah': surah,
  };

  /// Creates a Bookmark instance from stored data, Deserializes it
  /// Used when reading from local storage
  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      pageNumber: map['pageNumber'],
      surah: map['surah'],
    );
  }
}