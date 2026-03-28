import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';

/// Centralised helper for all local storage operations
/// Uses SharedPreferences as a lightweight persistence layer
class StorageManager {
  /// Preference keys
  static const _kCurrentPageKey = 'CurrentPage1';
  static const _kBookmarkKey = 'bookmarks1';
  static const _darkModeKey = 'dark_mode';
  static const _pageScaleKey = 'quran_single_page_scale';

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

  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? false;
  }

  static Future<void> saveDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
  }

  static Future<void> savePageScalePortrait(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pageScaleKey, value);
  }

  static Future<double> getPageScalePortrait() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_pageScaleKey) ?? 0.8; // default
  }

  static Future<void> savePageScaleLandscape(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pageScaleKey, value);
  }

  static Future<double> getPageScaleLandscape() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_pageScaleKey) ?? 0.9; // default
  }

  static Future<void> saveMushaf(String mushaf) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mushafTest1', mushaf);
    debugPrint('[MUSHAF] Saved mushaf $mushaf');
  }

  static Future<String> getMushaf() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mushafTest1') ?? 'indopak_tajweed';
  }

  static Future<void> ensureMushafDownloaded(
      String mushaf,
      int version,
      ) async {

    debugPrint('[STORAGE] ===== ENSURE MUSHAF =====');
    debugPrint('[STORAGE] Mushaf: $mushaf');
    debugPrint('[STORAGE] Target version: $version');

    bool upToDate = await isMushafUpToDate(mushaf, version);

    debugPrint('[STORAGE] Up to date: $upToDate');

    if (upToDate) {
      debugPrint('[STORAGE] Skipping download');
      return;
    }

    debugPrint('[STORAGE] Deleting old mushaf');
    await deleteOldMushaf(mushaf);

    debugPrint('[STORAGE] Downloading zip');
    final zipFile = await downloadMushafZip(mushaf);

    debugPrint('[STORAGE] Zip downloaded at ${zipFile.path}');

    debugPrint('[STORAGE] Unzipping...');
    await unzipMushaf(zipFile, mushaf);

    debugPrint('[STORAGE] Marking version saved');
    await markMushafDownloaded(mushaf, version);

    debugPrint('[STORAGE] Deleting zip');
    await zipFile.delete();

    debugPrint('[STORAGE] DONE');
  }

  static Future<bool> isMushafUpToDate(
      String mushaf,
      int version,
      ) async {

    final prefs = await SharedPreferences.getInstance();

    final savedVersion = prefs.getInt('${mushaf}_version3') ?? 0;

    return savedVersion == version;
  }

  static Future<void> markMushafDownloaded(
      String mushaf,
      int version,
      ) async {

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('${mushaf}_version3', version);
  }

  static Future<File> downloadMushafZip(String mushaf) async {

    final ref = FirebaseStorage.instance
        .ref()
        .child('Quran-images/quran_$mushaf.zip');

    final dir = await getApplicationDocumentsDirectory();

    final file = File('${dir.path}/quran_$mushaf.zip');

    debugPrint('[STORAGE] Downloading from Firebase: ${ref.fullPath}');
    debugPrint('[STORAGE] Saving to: ${file.path}');

    await ref.writeToFile(file);

    debugPrint('[STORAGE] Download complete');

    return file;
  }

  static Future<void> unzipMushaf(
      File zipFile,
      String mushaf,
      ) async {

    final bytes = await zipFile.readAsBytes();

    final archive = ZipDecoder().decodeBytes(bytes);

    final dir = await getApplicationDocumentsDirectory();

    final outputDir = Directory('${dir.path}/$mushaf');

    debugPrint('[STORAGE] Extracting to ${outputDir.path}');
    debugPrint('[STORAGE] Files in archive: ${archive.length}');

    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    int count = 0;

    for (final file in archive) {

      if (!file.isFile) continue;

      // only extract webp files
      if (!file.name.endsWith('.webp')) continue;

      final data = file.content as List<int>;

      // get just the filename (remove folders)
      final name = file.name.split('/').last;

      final outFile = File('${outputDir.path}/$name');

      await outFile.create(recursive: true);
      await outFile.writeAsBytes(data);

      count++;

      if (count % 50 == 0) {
        debugPrint('[STORAGE] Extracted $count files');
      }
    }

    debugPrint('[STORAGE] Extraction complete. Total files: $count');

    if (await dir.exists()) {
      for (final f in dir.listSync().take(20)) {
        debugPrint('[FILE] ${f.path}');
      }
    } else {
      debugPrint('[FILE] madani folder does not exist');
    }
  }

  static Future<void> deleteOldMushaf(String mushaf) async {

    final dir = await getApplicationDocumentsDirectory();

    final mushafDir = Directory('${dir.path}/$mushaf');

    if (mushafDir.existsSync()) {
      await mushafDir.delete(recursive: true);
    }
  }

  // static Future<void> ensureMadaniDownloaded() async {
  //   bool exists = await isMadaniDownloaded();
  //
  //   if (exists) return;
  //
  //   final zipFile = await downloadMadaniZip();
  //
  //   await unzipMadani(zipFile);
  //
  //   await markMadaniDownloaded();
  // }
  //
  // static Future<bool> isMadaniDownloaded() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   return prefs.getBool('madani_downloaded') ?? false;
  // }
  //
  // static Future<void> downloadMadani() async {
  //   /// download images / zip / assets etc
  //
  //   final prefs = await SharedPreferences.getInstance();
  //   await prefs.setBool('madani_downloaded', true);
  // }
  //
  // static Future<File> downloadMadaniZip() async {
  //   final ref = FirebaseStorage.instance.ref().child('Quran-images/quran_madani.zip');
  //   final dir = await getApplicationDocumentsDirectory();
  //   final file = File('${dir.path}/quran_madani.zip');
  //
  //   await ref.writeToFile(file);
  //
  //   return file;
  // }
  //
  // static Future<void> unzipMadani(File zipFile) async {
  //   final bytes = await zipFile.readAsBytes();
  //   final archive = ZipDecoder().decodeBytes(bytes);
  //
  //   final dir = await getApplicationDocumentsDirectory();
  //   final outputDir = Directory('${dir.path}/madani');
  //
  //   if (!outputDir.existsSync()) {
  //     outputDir.createSync(recursive: true);
  //   }
  //
  //   for (final file in archive) {
  //     final filename = '${outputDir.path}/${file.name}';
  //
  //     if (file.isFile) {
  //       final outFile = File(filename);
  //       await outFile.create(recursive: true);
  //       await outFile.writeAsBytes(file.content);
  //     }
  //   }
  // }

  static Future<void> markMadaniDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('madani_downloaded', true);
  }
}
