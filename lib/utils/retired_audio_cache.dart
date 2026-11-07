import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Best-effort startup migration. Only the retired provider's separate namespace
/// is removed; the canonical documents/audio EveryAyah cache is never traversed.
Future<void> removeRetiredAudioCache({
  Future<Directory> Function()? documents,
}) async {
  try {
    final root = await (documents ?? getApplicationDocumentsDirectory)();
    final path = '${root.path}/mp3quran';
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      // Dart's recursive delete removes nested links, not their targets.
      await Directory(path).delete(recursive: true);
    } else if (type == FileSystemEntityType.link) {
      await Link(path).delete();
    } else if (type == FileSystemEntityType.file) {
      await File(path).delete();
    }
  } catch (error) {
    // Cleanup must never block playback/startup; retry on the next launch.
    debugPrint('[AUDIO] Retired cache cleanup deferred: $error');
  }
}
