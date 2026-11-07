import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/quran_audio.dart';

/// No network API is consulted at runtime. A reviewed, hash-bound manifest must
/// be bundled before this flag can select the pilot. Release remains blocked.
abstract final class Mp3QuranPilot {
  static const enabled =
      !kReleaseMode && bool.fromEnvironment('EXPERIMENTAL_MP3QURAN_AL_MULK');

  // Intentionally absent: live v4 intervals have not passed a content audit.
  static const Mp3QuranManifest? verifiedManifest = null;

  static bool supports(AudioPlaybackPlan plan) =>
      plan.reciter.id == 'alafasy' &&
      plan.surah == 67 &&
      plan.sourceMode == AudioSourceMode.surah &&
      plan.repeatMode == AudioRepeatMode.range;
}

class Mp3QuranInterval {
  const Mp3QuranInterval(this.ayah, this.startMs, this.endMs);
  final int ayah, startMs, endMs;
  Duration get start => Duration(milliseconds: startMs);
  Duration get duration => Duration(milliseconds: endMs - startMs);
}

/// Only for the exact original Alafasy r1 / 067.mp3. Structural validation is
/// separate from the required content audit; constructing this is not an audit.
class Mp3QuranManifest {
  Mp3QuranManifest({
    required this.sha256,
    required this.bytes,
    required this.durationMs,
    required List<Mp3QuranInterval> intervals,
  }) : intervals = List.unmodifiable(intervals) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        bytes <= 0 ||
        durationMs <= 0) {
      throw ArgumentError('Invalid recording identity');
    }
    var previousEnd = 0, numbered = 0;
    final seen = <int>{};
    for (final interval in intervals) {
      if (interval.ayah < -1 ||
          interval.ayah > 30 ||
          !seen.add(interval.ayah) ||
          interval.startMs < previousEnd ||
          interval.endMs <= interval.startMs ||
          interval.endMs > durationMs) {
        throw ArgumentError('Invalid or overlapping ayah intervals');
      }
      if (interval.ayah > 0 && interval.ayah != ++numbered) {
        throw ArgumentError('Numbered ayahs must occur in order');
      }
      if (interval.ayah <= 0 && numbered > 0) {
        throw ArgumentError('Introductions must precede numbered ayahs');
      }
      previousEnd = interval.endMs;
    }
    if (numbered != 30) throw ArgumentError('All 30 ayahs are required');
  }
  static const url =
      'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/067.mp3';
  final String sha256;
  final int bytes, durationMs;
  final List<Mp3QuranInterval> intervals;

  Mp3QuranInterval? at(Duration position) {
    final ms = position.inMilliseconds;
    for (final interval in intervals) {
      if (ms >= interval.startMs && ms < interval.endMs) return interval;
    }
    return null; // Never invent coverage for gaps, prologue or tail.
  }

  Mp3QuranInterval ayah(int number) =>
      intervals.firstWhere((i) => i.ayah == number);
}

class Mp3QuranRepository {
  Mp3QuranRepository({
    Dio? dio,
    Future<Directory> Function()? directory,
    this.manifest,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(minutes: 2),
             ),
           ),
       _directory = directory ?? getApplicationDocumentsDirectory;
  final Mp3QuranManifest? manifest;
  final Dio _dio;
  final Future<Directory> Function() _directory;

  Future<bool> _matches(File file, Mp3QuranManifest identity) async =>
      await file.exists() &&
      await file.length() == identity.bytes &&
      (await crypto.sha256.bind(file.openRead()).first).toString() ==
          identity.sha256;

  Future<String> recording(
    CancelToken token, {
    void Function(double)? onProgress,
  }) async {
    final identity = manifest;
    if (identity == null) throw StateError('No content-verified timings');
    if (token.isCancelled) throw token.cancelError!;
    final root = await _directory();
    final file = File(
      '${root.path}/mp3quran/mishary-alafasy/r1/${identity.sha256}/067.mp3',
    );
    if (await _matches(file, identity)) {
      if (token.isCancelled) throw token.cancelError!;
      return file.path;
    }
    await file.parent.create(recursive: true);
    final part = File('${file.path}.${identityHashCode(token)}.part');
    try {
      await _dio.download(
        Mp3QuranManifest.url,
        part.path,
        cancelToken: token,
        onReceiveProgress: (received, total) =>
            onProgress?.call((received / identity.bytes).clamp(0, 1)),
      );
      if (!await _matches(part, identity)) {
        throw StateError('MP3Quran recording integrity mismatch');
      }
      if (token.isCancelled) throw token.cancelError!;
      await part.rename(file.path);
      return file.path;
    } finally {
      if (await part.exists()) await part.delete();
    }
  }
}
