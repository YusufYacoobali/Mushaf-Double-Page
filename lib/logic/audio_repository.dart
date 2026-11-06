import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/quran_audio.dart';
import '../utils/bismillah_sources.dart';

enum AudioFailureKind { connectivity, missing, corrupt, decoder, unavailable }

class AudioFailure implements Exception {
  const AudioFailure(this.kind, this.message);
  final AudioFailureKind kind;
  final String message;
  bool get recoverable =>
      kind != AudioFailureKind.missing && kind != AudioFailureKind.unavailable;
  @override
  String toString() => message;
}

abstract class AudioRecordingRepository {
  Future<String> recording(
    Reciter reciter,
    QuranAudioItem item,
    CancelToken token, {
    bool urgent = true,
    void Function(double)? onProgress,
  });
  Future<void> invalidate(Reciter reciter, QuranAudioItem item);
}

class _DownloadJob {
  _DownloadJob(
    this.key,
    this.reciter,
    this.item,
    this.token,
    this.urgent,
    this.onProgress,
  );
  final String key;
  final Reciter reciter;
  final QuranAudioItem item;
  final CancelToken token;
  bool urgent;
  void Function(double)? onProgress;
  final result = Completer<String>();
}

/// Cache paths for numbered ayahs are unchanged. A single scheduler bounds all
/// foreground, offline and speculative work to two requests.
class AudioRepository implements AudioRecordingRepository {
  AudioRepository({Dio? dio, Future<Directory> Function()? directory})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              sendTimeout: const Duration(seconds: 15),
            ),
          ),
      _directory = directory ?? getApplicationDocumentsDirectory;
  final Dio _dio;
  final Future<Directory> Function() _directory;
  final _pending = <_DownloadJob>[];
  final _jobs = <String, _DownloadJob>{};
  int _running = 0;

  static String audioId(int surah, int ayah) =>
      '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}';

  String filename(Reciter reciter, QuranAudioItem item) => item.isIntroduction
      ? BismillahSources.filename(reciter, item.surah)
      : '${audioId(item.surah, item.ayah!)}.mp3';

  Future<File> fileFor(Reciter reciter, QuranAudioItem item) async {
    final dir = await _directory();
    return File('${dir.path}/audio/${reciter.id}/${filename(reciter, item)}');
  }

  @override
  Future<void> invalidate(Reciter reciter, QuranAudioItem item) async {
    final file = await fileFor(reciter, item);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<String> recording(
    Reciter reciter,
    QuranAudioItem item,
    CancelToken token, {
    bool urgent = true,
    void Function(double)? onProgress,
  }) async {
    if (token.isCancelled) throw token.cancelError!;
    final key =
        '${identityHashCode(token)}:${reciter.id}:${filename(reciter, item)}';
    final existing = _jobs[key];
    if (existing != null) {
      existing.urgent |= urgent;
      existing.onProgress = onProgress ?? existing.onProgress;
      _pump();
      return existing.result.future;
    }
    final job = _DownloadJob(key, reciter, item, token, urgent, onProgress);
    _jobs[key] = job;
    _pending.add(job);
    // Defer scheduling so a burst of urgent requests precedes prefetch work.
    scheduleMicrotask(_pump);
    return job.result.future;
  }

  void _pump() {
    _pending.sort((a, b) => (b.urgent ? 1 : 0) - (a.urgent ? 1 : 0));
    while (_running < 2 && _pending.isNotEmpty) {
      final job = _pending.removeAt(0);
      _running++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_DownloadJob job) async {
    try {
      if (job.token.isCancelled) throw job.token.cancelError!;
      job.result.complete(await _obtain(job));
    } catch (e, stack) {
      job.result.completeError(e, stack);
    } finally {
      _running--;
      _jobs.remove(job.key);
      _pump();
    }
  }

  Future<String> _obtain(_DownloadJob job) async {
    final file = await fileFor(job.reciter, job.item);
    if (job.token.isCancelled) throw job.token.cancelError!;
    if (await file.exists()) {
      if (await validMp3(file)) return file.path;
      await file.delete();
    }
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.${identityHashCode(job)}.part');
    try {
      final requestToken = CancelToken();
      unawaited(
        job.token.whenCancel.then(
          (_) => requestToken.cancel('Session cancelled'),
        ),
      );
      final response = await _dio
          .download(
            'https://everyayah.com/data/${job.reciter.folder}/${filename(job.reciter, job.item)}',
            temp.path,
            cancelToken: requestToken,
            onReceiveProgress: (received, total) {
              if (!job.token.isCancelled && total > 0) {
                job.onProgress?.call(received / total);
              }
            },
          )
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              requestToken.cancel('Recording request timed out');
              throw const AudioFailure(
                AudioFailureKind.connectivity,
                'The recording download timed out. Check your connection.',
              );
            },
          );
      if (job.token.isCancelled) throw job.token.cancelError!;
      final type = response.headers.value('content-type')?.toLowerCase() ?? '';
      if (type.contains('text/') ||
          type.contains('json') ||
          !await validMp3(temp)) {
        throw const AudioFailure(
          AudioFailureKind.corrupt,
          'The downloaded recording is incomplete or is not valid MP3 audio.',
        );
      }
      if (job.token.isCancelled) throw job.token.cancelError!;
      // rename is atomic on the same filesystem; .part files are never playable.
      await temp.rename(file.path);
      return file.path;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      if (e.response?.statusCode == 404 || e.response?.statusCode == 410) {
        throw const AudioFailure(
          AudioFailureKind.missing,
          'This recording is missing from the reciter’s collection.',
        );
      }
      throw const AudioFailure(
        AudioFailureKind.connectivity,
        'Connection needed. Cached recordings remain available offline.',
      );
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Check MPEG Layer III frame structure, including ID3 tags and truncated
  /// frames. An HTML response, ID3-only file or a few random bytes is not audio.
  static Future<bool> validMp3(File file) async {
    if (await file.length() < 128) return false;
    return validMp3Bytes(await file.readAsBytes());
  }

  static bool validMp3Bytes(Uint8List bytes) {
    var offset = 0;
    if (bytes.length >= 10 &&
        bytes[0] == 73 &&
        bytes[1] == 68 &&
        bytes[2] == 51) {
      offset =
          10 +
          ((bytes[6] & 127) << 21) +
          ((bytes[7] & 127) << 14) +
          ((bytes[8] & 127) << 7) +
          (bytes[9] & 127);
      if (bytes[5] & 16 != 0) offset += 10;
    }
    var frames = 0;
    while (offset + 4 <= bytes.length) {
      if (bytes.length - offset == 128 &&
          bytes[offset] == 84 &&
          bytes[offset + 1] == 65 &&
          bytes[offset + 2] == 71) {
        return frames >= 2;
      }
      final a = bytes[offset + 1], b = bytes[offset + 2];
      if (bytes[offset] != 255 || a & 224 != 224) {
        // Some encoders append zero padding after the final frame.
        return frames >= 2 &&
            bytes.length - offset <= 2048 &&
            bytes.skip(offset).every((b) => b == 0);
      }
      final version = (a >> 3) & 3;
      final layer = (a >> 1) & 3;
      final rateIndex = (b >> 4) & 15;
      final sampleIndex = (b >> 2) & 3;
      if (version == 1 ||
          layer != 1 ||
          rateIndex == 0 ||
          rateIndex == 15 ||
          sampleIndex == 3) {
        return false;
      }
      const rates1 = [
        0,
        32,
        40,
        48,
        56,
        64,
        80,
        96,
        112,
        128,
        160,
        192,
        224,
        256,
        320,
      ];
      const rates2 = [
        0,
        8,
        16,
        24,
        32,
        40,
        48,
        56,
        64,
        80,
        96,
        112,
        128,
        144,
        160,
      ];
      final bitrate = (version == 3 ? rates1 : rates2)[rateIndex] * 1000;
      final sample =
          [44100, 48000, 32000][sampleIndex] ~/
          (version == 3
              ? 1
              : version == 2
              ? 2
              : 4);
      final length =
          (version == 3 ? 144 : 72) * bitrate ~/ sample + ((b >> 1) & 1);
      if (offset + length > bytes.length) return false;
      offset += length;
      frames++;
    }
    return frames >= 2 && offset == bytes.length;
  }
}
