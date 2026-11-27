import 'dart:io';

import 'package:flutter/services.dart';

/// Probe the original during normal queue preparation. Repeats and recovery
/// share the decision, including when a native output fails over to just_audio.
class RecordingStereoProbe {
  static const _channel = MethodChannel('quran/pcm');
  final _recent = <(String, int, DateTime), Future<bool>>{};

  Future<bool> inspect(String path) async {
    late final FileStat stat;
    try {
      stat = await File(path).stat();
    } on FileSystemException {
      return false;
    }
    if (stat.type != FileSystemEntityType.file) return false;
    final key = (path, stat.size, stat.modified);
    final decision = _recent.remove(key) ?? _measure(path);
    _recent[key] = decision;
    if (_recent.length > 16) _recent.remove(_recent.keys.first);
    return decision;
  }

  void forget(String path) => _recent.removeWhere((key, _) => key.$1 == path);

  Future<bool> _measure(String path) async {
    try {
      return await _channel.invokeMethod<bool>('needsStereoCorrection', {
            'path': path,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
