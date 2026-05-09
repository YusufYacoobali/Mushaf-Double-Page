import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/models/bookmark.dart';

/// Centralised helper for all local storage operations
/// Uses SharedPreferences as a lightweight persistence layer
class StorageManager {
  /// Preference keys
  static const _kCurrentPageKey = 'CurrentPage1';
  static const _kBookmarkKey = 'bookmarks1';
  static const _darkModeKey = 'dark_mode';
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

    debugPrint('[BOOKMARK] saved total ${existing.length}');
  }

  /// Retrieves all saved bookmarks
  /// Returns an empty list if none exist
  static Future<List<Bookmark>> getBookmarks(String currentMushaf) async {
    final prefs = await SharedPreferences.getInstance();

    debugPrint('[BOOKMARK] requested mushaf: $currentMushaf');

    final List<String>? jsonList = prefs.getStringList(_kBookmarkKey);

    if (jsonList == null) {
      debugPrint('[BOOKMARK] no bookmarks stored');
      return [];
    }

    debugPrint('[BOOKMARK] raw stored count: ${jsonList.length}');

    final bookmarks = jsonList.map((jsonStr) {
      final map = jsonDecode(jsonStr);
      final bookmark = Bookmark.fromMap(map);

      debugPrint(
        '[BOOKMARK] loaded page=${bookmark.pageNumber} mushaf=${bookmark.mushaf}',
      );

      return bookmark;
    }).toList();

    final filtered = bookmarks.where((b) => b.mushaf == currentMushaf).toList();

    debugPrint(
      '[BOOKMARK] after filter for "$currentMushaf": ${filtered.length}',
    );

    return filtered;
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
    await prefs.setDouble(_pageScalePortraitKey, value);
  }

  static Future<double> getPageScalePortrait() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_pageScalePortraitKey) ?? 0.8; // default
  }

  static Future<void> savePageScaleLandscape(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pageScaleLandscapeKey, value);
  }

  static Future<double> getPageScaleLandscape() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_pageScaleLandscapeKey) ?? 0.9; // default
  }

  static Future<void> saveMushaf(String mushaf) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mushaf', mushaf);
    debugPrint('[MUSHAF] Saved mushaf $mushaf');
  }

  static Future<String> getMushaf() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mushaf') ?? 'indopak_tajweed';
  }

  static Future<void> ensureMushafDownloaded(String mushaf, int version) async {
    debugPrint('[STORAGE] ===== ENSURE MUSHAF =====');
    debugPrint('[STORAGE] Mushaf: $mushaf');
    debugPrint('[STORAGE] Target version: $version');

    bool upToDate = await isMushafUpToDate(mushaf, version);
    final filesReady = await isMushafAvailable(mushaf);

    debugPrint('[STORAGE] Up to date: $upToDate');
    debugPrint('[STORAGE] Files ready: $filesReady');

    if (upToDate && filesReady) {
      debugPrint('[STORAGE] Skipping download');
      return;
    }

    debugPrint('[STORAGE] Downloading zip');
    final zipFile = await downloadMushafZip(mushaf);

    try {
      debugPrint('[STORAGE] Zip downloaded at ${zipFile.path}');

      debugPrint('[STORAGE] Unzipping...');
      final tempDir = await unzipMushaf(zipFile, mushaf);

      await validateMushafDirectory(tempDir, expectedMushafPageCount(mushaf));

      debugPrint('[STORAGE] Installing downloaded mushaf');
      await installMushafDirectory(tempDir, mushaf);

      debugPrint('[STORAGE] Marking version saved');
      await markMushafDownloaded(mushaf, version);

      debugPrint('[STORAGE] DONE');
    } finally {
      if (await zipFile.exists()) {
        debugPrint('[STORAGE] Deleting zip');
        await zipFile.delete();
      }
    }
  }

  static Future<bool> isMushafUpToDate(String mushaf, int version) async {
    final prefs = await SharedPreferences.getInstance();

    final savedVersion = prefs.getInt('${mushaf}_version3') ?? 0;

    return savedVersion == version;
  }

  static Future<bool> isMushafAvailable(String mushaf) async {
    final dir = await getApplicationDocumentsDirectory();
    final mushafDir = Directory('${dir.path}/$mushaf');

    if (!await mushafDir.exists()) return false;

    try {
      await validateMushafDirectory(mushafDir, expectedMushafPageCount(mushaf));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markMushafDownloaded(String mushaf, int version) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('${mushaf}_version3', version);
  }

  static Future<File> downloadMushafZip(String mushaf) async {
    final ref = FirebaseStorage.instance.ref().child(
      'Quran-images/quran_$mushaf.zip',
    );

    final dir = await getApplicationDocumentsDirectory();

    final file = File('${dir.path}/quran_$mushaf.zip');

    debugPrint('[STORAGE] Downloading from Firebase: ${ref.fullPath}');
    debugPrint('[STORAGE] Saving to: ${file.path}');

    await ref.writeToFile(file);

    debugPrint('[STORAGE] Download complete');

    return file;
  }

  static int expectedMushafPageCount(String mushaf) {
    switch (mushaf) {
      case 'madani':
        return 624;
      case 'indopak_tajweed':
      default:
        return 851;
    }
  }

  static Future<Directory> unzipMushaf(File zipFile, String mushaf) async {
    final bytes = await zipFile.readAsBytes();

    final archive = ZipDecoder().decodeBytes(bytes);

    final dir = await getApplicationDocumentsDirectory();

    final outputDir = Directory('${dir.path}/${mushaf}_pending');

    debugPrint('[STORAGE] Extracting to ${outputDir.path}');
    debugPrint('[STORAGE] Files in archive: ${archive.length}');

    if (outputDir.existsSync()) {
      await outputDir.delete(recursive: true);
    }
    await outputDir.create(recursive: true);

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
      debugPrint('[FILE] documents folder does not exist');
    }

    return outputDir;
  }

  static Future<void> validateMushafDirectory(
    Directory mushafDir,
    int expectedPageCount,
  ) async {
    final files = await mushafDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.webp'))
        .length;

    if (files < expectedPageCount) {
      throw StateError(
        'Downloaded mushaf is incomplete: $files/$expectedPageCount pages',
      );
    }
  }

  static Future<void> installMushafDirectory(
    Directory pendingDir,
    String mushaf,
  ) async {
    final dir = await getApplicationDocumentsDirectory();

    final mushafDir = Directory('${dir.path}/$mushaf');
    final backupDir = Directory('${dir.path}/${mushaf}_backup');

    if (backupDir.existsSync()) {
      await backupDir.delete(recursive: true);
    }

    if (mushafDir.existsSync()) {
      await mushafDir.rename(backupDir.path);
    }

    try {
      await pendingDir.rename(mushafDir.path);
      if (backupDir.existsSync()) {
        await backupDir.delete(recursive: true);
      }
    } catch (_) {
      if (mushafDir.existsSync()) {
        await mushafDir.delete(recursive: true);
      }
      if (backupDir.existsSync()) {
        await backupDir.rename(mushafDir.path);
      }
      rethrow;
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
