import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Downloads an edition into staging, then swaps it into the reader's document directory.
abstract final class MushafInstaller {
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
