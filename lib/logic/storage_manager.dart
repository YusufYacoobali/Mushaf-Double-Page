import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';

/// Centralised helper for all local storage operations
/// Uses SharedPreferences as a lightweight persistence layer
class StorageManager {
  /// Preference keys
  static const _kCurrentPageKey = 'CurrentPage1';
  static const _kBookmarkKey = 'bookmarks1';
  static const _kOptimizedPortraitKey = 'optimizedPortrait';
  static const _kOptimizedLandscapeKey = 'optimizedLandscape';

  /// Saves the current page number
  /// Skips saving for page 0 (start) and page 851 (dua/end)
  static Future<void> saveCurrentPage(int page) async {
    if (page != 0 && page != 851) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kCurrentPageKey, page);
    }
  }

  /// Retrieves the last saved page number
  /// Defaults to 0 if no value has been stored yet
  static Future<int> getCurrentPage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCurrentPageKey) ?? 0;
  }

  /// Persists the list of bookmarks
  /// Each bookmark is stored as a JSON string
  static Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsonList =
    bookmarks.map((b) => jsonEncode(b.toMap())).toList();
    await prefs.setStringList(_kBookmarkKey, jsonList);
  }

  /// Retrieves all saved bookmarks
  /// Returns an empty list if none exist
  static Future<List<Bookmark>> getBookmarks() async {
    final prefs = await SharedPreferences.getInstance();

    final List<String>? jsonList = prefs.getStringList(_kBookmarkKey);
    if (jsonList == null) return [];

    return jsonList.map((jsonStr) {
      final bookmark = Bookmark.fromMap(jsonDecode(jsonStr));

      // Fill surah if it was null
      bookmark.surah ??= surahNameFromPage(bookmark.pageNumber);
      return bookmark;
    }).toList();
  }

  /// Saves the optimized portrait mode setting
  static Future<void> saveOptimizedPortrait(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptimizedPortraitKey, value);
  }

  /// Retrieves the optimized portrait mode setting
  static Future<bool> getOptimizedPortrait() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOptimizedPortraitKey) ?? false;
  }

  /// Saves the optimized landscape mode setting
  static Future<void> saveOptimizedLandscape(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptimizedLandscapeKey, value);
  }

  /// Retrieves the optimized landscape mode setting
  static Future<bool> getOptimizedLandscape() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOptimizedLandscapeKey) ?? false;
  }
}
