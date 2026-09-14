import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:async';

import 'package:archive/archive.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/models/bookmark.dart';

typedef MushafProgressCallback = void Function(MushafDownloadProgress progress);

class MushafDownloadProgress {
  final String message;
  final double? value;

  const MushafDownloadProgress(this.message, [this.value]);
}

void _extractMushafZipInIsolate(List<Object?> args) {
  final zipPath = args[0] as String;
  final outputPath = args[1] as String;
  final expectedPageCount = args[2] as int;
  final sendPort = args[3] as SendPort;

  try {
    final count = _extractMushafZip(
      zipPath,
      outputPath,
      expectedPageCount,
      sendPort,
    );
    sendPort.send({'type': 'done', 'count': count});
  } catch (e, stackTrace) {
    sendPort.send({
      'type': 'error',
      'error': e.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }
}

int _extractMushafZip(
  String zipPath,
  String outputPath,
  int expectedPageCount,
  SendPort sendPort,
) {
  final input = InputFileStream(zipPath);

  try {
    final archive = ZipDecoder().decodeStream(input);
    var count = 0;

    for (final entry in archive) {
      if (!entry.isFile || !entry.name.endsWith('.webp')) continue;

      final name = entry.name.split('/').last.split('\\').last;
      if (name.isEmpty) continue;

      final output = OutputFileStream('$outputPath/$name');
      try {
        entry.writeContent(output);
        count++;
        if (count == expectedPageCount || count % 25 == 0) {
          sendPort.send({'type': 'progress', 'count': count});
        }
      } finally {
        output.closeSync();
      }
    }

    archive.clear();
    return count;
  } finally {
    input.closeSync();
  }
}

/// Centralised helper for all local storage operations
/// Uses SharedPreferences as a lightweight persistence layer
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
  }) async {
    onProgress?.call(const MushafDownloadProgress('Checking local Mushaf'));

    final upToDate = await isMushafUpToDate(mushaf, version);
    final filesReady = await isMushafAvailable(mushaf);

    if (upToDate && filesReady) return;

    onProgress?.call(const MushafDownloadProgress('Downloading Mushaf', 0));
    final zipFile = await downloadMushafZip(mushaf, onProgress: onProgress);

    try {
      onProgress?.call(const MushafDownloadProgress('Preparing pages', 0));
      final tempDir = await unzipMushaf(
        zipFile,
        mushaf,
        onProgress: onProgress,
      );

      onProgress?.call(const MushafDownloadProgress('Installing pages'));
      await installMushafDirectory(tempDir, mushaf);
      await markMushafDownloaded(mushaf, version);

      onProgress?.call(const MushafDownloadProgress('Opening Mushaf', 1));
    } finally {
      if (await zipFile.exists()) await zipFile.delete();
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
    final expectedPageCount = expectedMushafPageCount(mushaf);

    if (!await mushafDir.exists()) return false;

    final firstPage = File('${mushafDir.path}/1.webp');
    final lastPage = File('${mushafDir.path}/$expectedPageCount.webp');

    return await firstPage.exists() && await lastPage.exists();
  }

  static Future<void> markMushafDownloaded(String mushaf, int version) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('${mushaf}_version3', version);
  }

  static Future<File> downloadMushafZip(
    String mushaf, {
    MushafProgressCallback? onProgress,
  }) async {
    final ref = FirebaseStorage.instance.ref().child(
      'Quran-images/quran_$mushaf.zip',
    );

    final dir = await getApplicationDocumentsDirectory();

    final file = File('${dir.path}/quran_$mushaf.zip');

    final task = ref.writeToFile(file);
    final subscription = task.snapshotEvents.listen((snapshot) {
      final totalBytes = snapshot.totalBytes;
      if (totalBytes <= 0) return;

      final value = snapshot.bytesTransferred / totalBytes;
      final percent = (value * 100).clamp(0, 100).round();

      onProgress?.call(
        MushafDownloadProgress('Downloading Mushaf $percent%', value),
      );
    });

    try {
      await task;
    } finally {
      await subscription.cancel();
    }

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

  static Future<Directory> unzipMushaf(
    File zipFile,
    String mushaf, {
    MushafProgressCallback? onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();

    final outputDir = Directory('${dir.path}/${mushaf}_pending');
    final expectedPageCount = expectedMushafPageCount(mushaf);

    if (outputDir.existsSync()) {
      await outputDir.delete(recursive: true);
    }
    await outputDir.create(recursive: true);

    final count = await _extractMushafZipWithProgress(
      zipFile.path,
      outputDir.path,
      expectedPageCount,
      onProgress: onProgress,
    );

    validateExtractedPageCount(count, expectedPageCount);

    return outputDir;
  }

  static Future<int> _extractMushafZipWithProgress(
    String zipPath,
    String outputPath,
    int expectedPageCount, {
    MushafProgressCallback? onProgress,
  }) async {
    final receivePort = ReceivePort();
    final completer = Completer<int>();

    final isolate = await Isolate.spawn(_extractMushafZipInIsolate, [
      zipPath,
      outputPath,
      expectedPageCount,
      receivePort.sendPort,
    ]);

    late final StreamSubscription subscription;
    subscription = receivePort.listen((message) {
      if (message is! Map) return;

      switch (message['type']) {
        case 'progress':
          final count = message['count'] as int;
          final value = (count / expectedPageCount).clamp(0.0, 1.0);
          onProgress?.call(
            MushafDownloadProgress(
              'Preparing pages $count/$expectedPageCount',
              value,
            ),
          );
          break;
        case 'done':
          if (!completer.isCompleted) {
            completer.complete(message['count'] as int);
          }
          break;
        case 'error':
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(message['error'] as String),
              StackTrace.fromString(message['stackTrace'] as String),
            );
          }
          break;
      }
    });

    try {
      return await completer.future;
    } finally {
      isolate.kill(priority: Isolate.immediate);
      await subscription.cancel();
      receivePort.close();
    }
  }

  static void validateExtractedPageCount(int files, int expectedPageCount) {
    if (files < expectedPageCount) {
      throw StateError(
        'Downloaded mushaf is incomplete: $files/$expectedPageCount pages',
      );
    }
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
}
