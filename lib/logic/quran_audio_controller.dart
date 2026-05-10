import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:path_provider/path_provider.dart';

enum QuranAudioErrorKind { none, connectionRequired, playback }

class _StaleAudioRequest implements Exception {
  const _StaleAudioRequest();
}

class AudioDownloadState {
  final bool active;
  final int completed;
  final int total;
  final String message;

  const AudioDownloadState({
    required this.active,
    required this.completed,
    required this.total,
    required this.message,
  });

  const AudioDownloadState.idle()
    : active = false,
      completed = 0,
      total = 0,
      message = '';

  double? get progress {
    if (total == 0) return null;
    return completed / total;
  }
}

class QuranAudioController extends ChangeNotifier {
  QuranAudioController._() {
    _player.currentIndexStream.listen((_) => notifyListeners());
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _downloadState = const AudioDownloadState.idle();
      }
      notifyListeners();
    });
    _player.errorStream.listen((error) {
      _error = 'Audio playback failed. Please try again.';
      debugPrint('[AUDIO] Playback error: $error');
      notifyListeners();
    });
  }

  static final QuranAudioController instance = QuranAudioController._();

  final AudioPlayer _player = AudioPlayer(maxSkipsOnError: 2);
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 3),
    ),
  );

  AudioPlaybackPlan? _plan;
  AudioDownloadState _downloadState = const AudioDownloadState.idle();
  String? _error;
  QuranAudioErrorKind _errorKind = QuranAudioErrorKind.none;
  bool _preparing = false;
  int _playRequestId = 0;
  CancelToken? _downloadCancelToken;

  AudioPlayer get player => _player;
  AudioPlaybackPlan? get plan => _plan;
  AudioDownloadState get downloadState => _downloadState;
  String? get error => _error;
  QuranAudioErrorKind get errorKind => _errorKind;
  bool get preparing => _preparing;
  bool get playing => _player.playing;
  ProcessingState get processingState => _player.processingState;
  bool get hasPlan => _plan != null;

  int? get currentIndex => _player.currentIndex;
  int get totalItems => _player.sequence?.length ?? 0;

  MediaItem? get currentMediaItem {
    final tag = _player.sequenceState?.currentSource?.tag;
    return tag is MediaItem ? tag : null;
  }

  int? get currentSurah => currentMediaItem?.extras?['surah'] as int?;
  int? get currentAyah => currentMediaItem?.extras?['ayah'] as int?;
  int? get currentRepeat => currentMediaItem?.extras?['cycle'] as int?;

  Future<void> playPlan(AudioPlaybackPlan plan) async {
    final requestId = ++_playRequestId;
    _downloadCancelToken?.cancel('Replaced by another audio request');
    final cancelToken = CancelToken();
    _downloadCancelToken = cancelToken;

    _preparing = true;
    _error = null;
    _errorKind = QuranAudioErrorKind.none;
    _downloadState = const AudioDownloadState.idle();
    _plan = plan;
    notifyListeners();

    try {
      await _player.stop();
      _throwIfStale(requestId);

      final localSources = await _prepareSources(plan, requestId, cancelToken);
      _throwIfStale(requestId);

      await _player.setLoopMode(
        plan.infiniteRepeat ? LoopMode.all : LoopMode.off,
      );
      _throwIfStale(requestId);

      await _player.setAudioSources(localSources);
      _throwIfStale(requestId);

      await _player.play();
    } on DioException catch (e) {
      if (!_isCurrentRequest(requestId) || CancelToken.isCancel(e)) return;
      _errorKind = QuranAudioErrorKind.connectionRequired;
      _error =
          'Connection needed to download this audio the first time. Once downloaded, it will play offline.';
      debugPrint('[AUDIO] Download failed: $e');
    } on _StaleAudioRequest {
      return;
    } catch (e) {
      if (!_isCurrentRequest(requestId)) return;
      _errorKind = QuranAudioErrorKind.playback;
      _error = 'Could not prepare audio. Please try again.';
      debugPrint('[AUDIO] Prepare failed: $e');
    } finally {
      if (_isCurrentRequest(requestId)) {
        _preparing = false;
        _downloadState = const AudioDownloadState.idle();
        if (_downloadCancelToken == cancelToken) {
          _downloadCancelToken = null;
        }
        notifyListeners();
      }
    }
  }

  void clearError() {
    _error = null;
    _errorKind = QuranAudioErrorKind.none;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }

    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero, index: 0);
    }
    await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
    _downloadState = const AudioDownloadState.idle();
    notifyListeners();
  }

  Future<void> seekNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  Future<void> seekPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  bool _isCurrentRequest(int requestId) => requestId == _playRequestId;

  void _throwIfStale(int requestId) {
    if (!_isCurrentRequest(requestId)) throw const _StaleAudioRequest();
  }

  Future<List<AudioSource>> _prepareSources(
    AudioPlaybackPlan plan,
    int requestId,
    CancelToken cancelToken,
  ) async {
    await _ensureCached(plan, requestId, cancelToken);
    _throwIfStale(requestId);
    _backgroundCacheSurah(plan, cancelToken);
    return [
      for (final verse in plan.playbackVerses())
        AudioSource.file(
          await _pathFor(plan.reciter, verse.surah, verse.ayah),
          tag: MediaItem(
            id: '${plan.reciter.id}-${verse.surah}-${verse.ayah}-${verse.cycle}',
            album: plan.surahInfo.name,
            artist: plan.reciter.name,
            title:
                '${plan.surahInfo.name} ${verse.surah}:${verse.ayah}'
                ' (${verse.cycle}/${plan.repeatLabel})',
            extras: {
              'surah': verse.surah,
              'ayah': verse.ayah,
              'cycle': verse.cycle,
              'repeatCount': plan.repeatCount ?? -1,
            },
          ),
        ),
    ];
  }

  void _backgroundCacheSurah(AudioPlaybackPlan plan, CancelToken cancelToken) {
    final played = {
      for (var a = plan.effectiveFromAyah; a <= plan.effectiveToAyah; a++) a,
    };
    () async {
      for (var ayah = 1; ayah <= plan.ayahCount; ayah++) {
        if (cancelToken.isCancelled) return;
        if (played.contains(ayah)) continue;
        try {
          final file = File(await _pathFor(plan.reciter, plan.surah, ayah));
          if (await file.exists() && await file.length() > 0) continue;
          await _downloadVerse(plan.reciter, plan.surah, ayah, cancelToken);
        } catch (_) {
          return;
        }
      }
    }();
  }

  Future<void> _ensureCached(
    AudioPlaybackPlan plan,
    int requestId,
    CancelToken cancelToken,
  ) async {
    final missing = <AudioVerse>[];
    for (final verse in plan.uniqueVerses()) {
      _throwIfStale(requestId);
      final file = File(await _pathFor(plan.reciter, verse.surah, verse.ayah));
      if (!await file.exists() || await file.length() == 0) {
        missing.add(verse);
      }
    }

    if (missing.isEmpty) return;

    for (var i = 0; i < missing.length; i++) {
      _throwIfStale(requestId);
      final verse = missing[i];
      _downloadState = AudioDownloadState(
        active: true,
        completed: i,
        total: missing.length,
        message:
            'Downloading ${plan.reciter.name} '
            '${verse.surah}:${verse.ayah}',
      );
      notifyListeners();

      await _downloadVerse(plan.reciter, verse.surah, verse.ayah, cancelToken);
      _throwIfStale(requestId);
    }

    _downloadState = const AudioDownloadState.idle();
    notifyListeners();
  }

  Future<void> _downloadVerse(
    Reciter reciter,
    int surah,
    int ayah,
    CancelToken cancelToken,
  ) async {
    final path = await _pathFor(reciter, surah, ayah);
    final file = File(path);
    await file.parent.create(recursive: true);

    final tempPath = '$path.part';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    try {
      await _dio.download(
        _urlFor(reciter, surah, ayah),
        tempPath,
        cancelToken: cancelToken,
      );
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(path);
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  static String audioId(int surah, int ayah) {
    return '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}';
  }

  static String _urlFor(Reciter reciter, int surah, int ayah) {
    return 'https://everyayah.com/data/${reciter.folder}/${audioId(surah, ayah)}.mp3';
  }

  Future<String> _pathFor(Reciter reciter, int surah, int ayah) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/audio/${reciter.id}/${audioId(surah, ayah)}.mp3';
  }
}
