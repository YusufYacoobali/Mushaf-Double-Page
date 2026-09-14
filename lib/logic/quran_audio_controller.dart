import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  QuranAudioController._({
    AudioPlayer? player,
    Future<List<AudioSource>> Function(AudioPlaybackPlan)? prepareSources,
  }) : _player = player ?? AudioPlayer(maxSkipsOnError: 0),
       _sourcePreparer = prepareSources {
    _player.currentIndexStream.listen((index) {
      _handleCurrentIndex(index);
      notifyListeners();
    });
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _downloadState = const AudioDownloadState.idle();
        _handleCompletedPlayback();
      }
      notifyListeners();
    });
    _player.errorStream.listen((error) {
      debugPrint('[AUDIO] Playback source error: $error');
      _errorKind = QuranAudioErrorKind.playback;
      _error = 'Audio playback failed. Please try again.';
      notifyListeners();
    });
  }

  static final QuranAudioController instance = QuranAudioController._();

  @visibleForTesting
  factory QuranAudioController.forTesting({
    required AudioPlayer player,
    required Future<List<AudioSource>> Function(AudioPlaybackPlan)
    prepareSources,
  }) => QuranAudioController._(player: player, prepareSources: prepareSources);

  final AudioPlayer _player;
  final Future<List<AudioSource>> Function(AudioPlaybackPlan)? _sourcePreparer;
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
  bool _restartingInfinite = false;
  bool _advancingRangeRepeat = false;
  int _rangeCycle = 1;
  int? _lastIndex;
  int _playRequestId = 0;
  CancelToken? _downloadCancelToken;
  Uri? _artworkUri;
  Directory? _audioDirectory;

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
  int get totalItems => _player.sequence.length;

  MediaItem? get currentMediaItem {
    final tag = _player.sequenceState.currentSource?.tag;
    return tag is MediaItem ? tag : null;
  }

  int? get currentSurah => currentMediaItem?.extras?['surah'] as int?;
  int? get currentAyah => currentMediaItem?.extras?['ayah'] as int?;
  int? get currentRepeat {
    if (_plan?.repeatMode == AudioRepeatMode.range) return _rangeCycle;
    return currentMediaItem?.extras?['cycle'] as int?;
  }

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
    _rangeCycle = 1;
    _lastIndex = null;
    _advancingRangeRepeat = false;
    _restartingInfinite = false;
    notifyListeners();

    try {
      await _player.stop();
      _throwIfStale(requestId);

      final localSources =
          await (_sourcePreparer?.call(plan) ??
              _prepareSources(plan, requestId, cancelToken));
      _throwIfStale(requestId);

      await _player.setAudioSources(localSources);
      _throwIfStale(requestId);

      await _player.setLoopMode(
        plan.infiniteRepeat ? LoopMode.all : LoopMode.off,
      );
      _throwIfStale(requestId);

      _startPlayback(requestId);
    } on DioException catch (e) {
      if (!_isCurrentRequest(requestId) || CancelToken.isCancel(e)) return;
      _errorKind = QuranAudioErrorKind.connectionRequired;
      _error =
          'Connection needed to download this audio the first time. Once downloaded, it will play offline.';
    } on _StaleAudioRequest {
      return;
    } catch (e) {
      if (!_isCurrentRequest(requestId)) return;
      _errorKind = QuranAudioErrorKind.playback;
      _error = 'Could not prepare audio. Please try again.';
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

  // AudioPlayer.play completes when playback ends, not when it starts.
  // Never await it while holding the preparation or repeat guard.
  void _startPlayback(int requestId) {
    unawaited(
      _player.play().catchError((Object error) {
        if (!_isCurrentRequest(requestId)) return;
        _errorKind = QuranAudioErrorKind.playback;
        _error = 'Audio playback failed. Please try again.';
        notifyListeners();
      }),
    );
  }

  void clearError() {
    _error = null;
    _errorKind = QuranAudioErrorKind.none;
    notifyListeners();
  }

  void _handleCurrentIndex(int? index) {
    final plan = _plan;
    if (plan == null || plan.repeatMode != AudioRepeatMode.range) return;
    if (index == null) return;

    final previous = _lastIndex;
    _lastIndex = index;

    if (previous != null && index < previous && plan.infiniteRepeat) {
      _rangeCycle++;
    }
  }

  void _handleCompletedPlayback() {
    final plan = _plan;
    if (plan == null || _preparing) return;

    if (plan.repeatMode == AudioRepeatMode.range &&
        !plan.infiniteRepeat &&
        _rangeCycle < plan.visibleRepeatCount) {
      _advanceFiniteRangeRepeat();
      return;
    }

    if (plan.infiniteRepeat) {
      _restartInfinitePlayback();
    }
  }

  Future<void> _advanceFiniteRangeRepeat() async {
    if (_advancingRangeRepeat) return;
    _advancingRangeRepeat = true;
    final requestId = _playRequestId;

    try {
      final plan = _plan;
      if (plan == null ||
          plan.repeatMode != AudioRepeatMode.range ||
          plan.infiniteRepeat ||
          _rangeCycle >= plan.visibleRepeatCount) {
        return;
      }

      _rangeCycle++;
      _lastIndex = null;
      await _player.seek(Duration.zero, index: 0);
      if (_isCurrentRequest(requestId) && _plan == plan) {
        _startPlayback(requestId);
      }
    } catch (e) {
      debugPrint('[AUDIO] Range repeat advance failed: $e');
    } finally {
      if (_isCurrentRequest(requestId)) _advancingRangeRepeat = false;
      notifyListeners();
    }
  }

  Future<void> _restartInfinitePlayback() async {
    if (_restartingInfinite) return;
    _restartingInfinite = true;
    final requestId = _playRequestId;

    try {
      final plan = _plan;
      if (plan == null || !plan.infiniteRepeat) return;

      await _player.seek(Duration.zero, index: 0);
      if (_isCurrentRequest(requestId) && _plan == plan) {
        _startPlayback(requestId);
      }
    } catch (e) {
      debugPrint('[AUDIO] Infinite repeat restart failed: $e');
    } finally {
      if (_isCurrentRequest(requestId)) _restartingInfinite = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }

    if (_player.processingState == ProcessingState.completed) {
      _rangeCycle = 1;
      await _player.seek(Duration.zero, index: 0);
    }
    _startPlayback(_playRequestId);
  }

  Future<void> stop() async {
    ++_playRequestId;
    _downloadCancelToken?.cancel('Playback stopped');
    _downloadCancelToken = null;
    _preparing = false;
    _advancingRangeRepeat = false;
    _restartingInfinite = false;
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
    final artworkUri = await _audioArtworkUri();
    return [
      for (final verse in _playbackVersesForPlayer(plan))
        AudioSource.file(
          await _pathFor(plan.reciter, verse.surah, verse.ayah),
          tag: MediaItem(
            id: '${plan.reciter.id}-${verse.surah}-${verse.ayah}-${verse.cycle}',
            album: plan.sourceMode == AudioSourceMode.playlist
                ? 'Your surah queue'
                : plan.surahInfo.name,
            artist: plan.reciter.name,
            artUri: artworkUri,
            title:
                '${quranSurahs[verse.surah - 1].name} ${verse.surah}:${verse.ayah}'
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

  List<AudioVerse> _playbackVersesForPlayer(AudioPlaybackPlan plan) {
    if (plan.repeatMode == AudioRepeatMode.range) {
      return plan.uniqueVerses();
    }

    return plan.playbackVerses();
  }

  Future<Uri?> _audioArtworkUri() async {
    final cached = _artworkUri;
    if (cached != null) return cached;

    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/audio_artwork.jpeg');
      if (!await file.exists() || await file.length() == 0) {
        await file.parent.create(recursive: true);
        final data = await rootBundle.load('assets/icon/app_icon.jpeg');
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      _artworkUri = file.uri;
      return _artworkUri;
    } catch (e) {
      debugPrint('[AUDIO] Could not prepare lock screen artwork: $e');
      return null;
    }
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

    final tempPath = '$path.${identityHashCode(cancelToken)}.part';
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
    final dir = _audioDirectory ??= await getApplicationDocumentsDirectory();
    return '${dir.path}/audio/${reciter.id}/${audioId(surah, ayah)}.mp3';
  }
}
