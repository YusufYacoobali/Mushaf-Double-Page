import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark.dart';
import 'mushaf_installer.dart';

export 'mushaf_installer.dart'
    show MushafDownloadProgress, MushafProgressCallback;

/// Reader preferences and bookmarks, with the original installation API for callers.
class StorageManager {
  /// Preference keys
  static const _kCurrentPageKey = 'CurrentPage1';
  static const _kBookmarkKey = 'bookmarks1';
  static const _darkModeKey = 'dark_mode';
  static const _appDarkModeKey = 'app_dark_mode';
  static const _ayahHighlightingKey = 'ayah_highlighting_enabled';
  static const _pageScalePortraitKey = 'quran_single_page_scale';
  static const _pageScaleLandscapeKey = 'quran_landscape_page_scale';

  /// Saves the current page number
  /// Skips saving boundary pages such as the start screen and final page.
  static Future<void> saveCurrentPage(int page, {int? maxPage}) async {
    final isBoundaryPage = page == 0 || (maxPage != null && page >= maxPage);

    if (!isBoundaryPage) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kCurrentPageKey, page);
    }
  }

  /// Retrieves the last saved page number
  /// Defaults to 0 if no value has been stored yet
  static Future<int> getCurrentPage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCurrentPageKey) ?? 1;
  }

  /// Persists the list of bookmarks
  /// Each bookmark is stored as a JSON string
  static Future<void> saveBookmarks(
    List<Bookmark> bookmarks, {
    String? mushaf,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final List<String>? existingJson = prefs.getStringList(_kBookmarkKey);

    final existing = existingJson == null
        ? <Bookmark>[]
        : existingJson.map((e) => Bookmark.fromMap(jsonDecode(e))).toList();

    final targetMushaf =
        mushaf ?? (bookmarks.isNotEmpty ? bookmarks.first.mushaf : null);

    if (targetMushaf != null) {
      // remove old bookmarks for this mushaf only
      existing.removeWhere((b) => b.mushaf == targetMushaf);

      // add the updated ones
      existing.addAll(bookmarks);
    }

    final jsonList = existing.map((b) => jsonEncode(b.toMap())).toList();

    await prefs.setStringList(_kBookmarkKey, jsonList);
  }

  /// Retrieves all saved bookmarks
  /// Returns an empty list if none exist
  static Future<List<Bookmark>> getBookmarks(String currentMushaf) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? jsonList = prefs.getStringList(_kBookmarkKey);
    if (jsonList == null) return [];

    return jsonList
        .map((s) => Bookmark.fromMap(jsonDecode(s)))
        .where((b) => b.mushaf == currentMushaf)
        .toList();
  }

  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  static Future<void> saveDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
  }

  static Future<bool> getAppDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_appDarkModeKey) ?? false;
  }

  static Future<void> saveAppDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appDarkModeKey, value);
  }

  static Future<bool> getAyahHighlightingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ayahHighlightingKey) ?? true;
  }

  static Future<void> saveAyahHighlightingEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ayahHighlightingKey, value);
  }

  static Future<bool> getControlsArrowOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('reader_controls_arrow_only') ?? false;
  }

  static Future<void> saveControlsArrowOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reader_controls_arrow_only', value);
  }

  static Future<bool> getReaderWhiteBackground() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('reader_white_background') ?? false;
  }

  static Future<void> saveReaderWhiteBackground(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reader_white_background', value);
  }

  static Future<void> savePageScalePortrait(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pageScalePortraitKey, value.clamp(0.7, 1.0));
  }

  static Future<double> getPageScalePortrait() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_pageScalePortraitKey) ?? 0.8).clamp(0.7, 1.0);
  }

  static Future<void> savePageScaleLandscape(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pageScaleLandscapeKey, value.clamp(0.6, 1.0));
  }

  static Future<double> getPageScaleLandscape() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_pageScaleLandscapeKey) ?? 0.9).clamp(0.6, 1.0);
  }

  static Future<void> saveMushaf(String mushaf) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mushaf', mushaf);
  }

  static Future<String> getMushaf() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mushaf') ?? 'indopak_tajweed';
  }

  static Future<void> ensureMushafDownloaded(
    String mushaf,
    int version, {
    MushafProgressCallback? onProgress,
  }) => MushafInstaller.ensureMushafDownloaded(
    mushaf,
    version,
    onProgress: onProgress,
  );
  static Future<bool> isMushafUpToDate(String mushaf, int version) =>
      MushafInstaller.isMushafUpToDate(mushaf, version);
  static Future<bool> isMushafAvailable(String mushaf) =>
      MushafInstaller.isMushafAvailable(mushaf);
  static Future<void> markMushafDownloaded(String mushaf, int version) =>
      MushafInstaller.markMushafDownloaded(mushaf, version);
  static Future<File> downloadMushafZip(
    String mushaf, {
    MushafProgressCallback? onProgress,
  }) => MushafInstaller.downloadMushafZip(mushaf, onProgress: onProgress);
  static int expectedMushafPageCount(String mushaf) =>
      MushafInstaller.expectedMushafPageCount(mushaf);
  static Future<Directory> unzipMushaf(
    File zipFile,
    String mushaf, {
    MushafProgressCallback? onProgress,
  }) => MushafInstaller.unzipMushaf(zipFile, mushaf, onProgress: onProgress);
  static void validateExtractedPageCount(int files, int expectedPageCount) =>
      MushafInstaller.validateExtractedPageCount(files, expectedPageCount);
  static Future<void> validateMushafDirectory(
    Directory mushafDir,
    int expectedPageCount,
  ) => MushafInstaller.validateMushafDirectory(mushafDir, expectedPageCount);
  static Future<void> installMushafDirectory(
    Directory pendingDir,
    String mushaf,
  ) => MushafInstaller.installMushafDirectory(pendingDir, mushaf);
}
