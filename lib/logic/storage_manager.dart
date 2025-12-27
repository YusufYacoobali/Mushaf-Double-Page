import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart'; // your separate mapper file

class StorageManager {
  static const _kCurrentPageKey = 'CurrentPage1';
  static const _kBookmarkKey = 'bookmarks1';
  static const _kOptimizedPortraitKey = 'optimizedPortrait';
  static const _kOptimizedLandscapeKey = 'optimizedLandscape';

  // Save current page
  static Future<void> saveCurrentPage(int page) async {
    if (page != 0 && page != 851) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kCurrentPageKey, page);
    }
  }

  // Get current page
  static Future<int> getCurrentPage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCurrentPageKey) ?? 0;
  }

  // Save bookmarks
  static Future<void> saveBookmarks(List<Bookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsonList =
    bookmarks.map((b) => jsonEncode(b.toMap())).toList();
    await prefs.setStringList(_kBookmarkKey, jsonList);
  }

  // Get bookmarks
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

  // Save optimized portrait state
  static Future<void> saveOptimizedPortrait(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptimizedPortraitKey, value);
  }

  // Get optimized portrait state
  static Future<bool> getOptimizedPortrait() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOptimizedPortraitKey) ?? false;
  }

  // Save optimized landscape state
  static Future<void> saveOptimizedLandscape(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOptimizedLandscapeKey, value);
  }

  // Get optimized landscape state
  static Future<bool> getOptimizedLandscape() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOptimizedLandscapeKey) ?? false;
  }
}
