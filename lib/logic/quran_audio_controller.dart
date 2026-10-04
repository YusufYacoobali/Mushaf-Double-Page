import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../progress/journey_store.dart';
import '../progress/journey_tracking.dart';
import '../progress/reading_progress_store.dart';
import '../utils/audio_artwork.dart';

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
    bool trackJourney = true,
    Future<List<AudioSource>> Function(AudioPlaybackPlan)? prepareSources,
  }) : _player = player ?? AudioPlayer(maxSkipsOnError: 0),
       _sourcePreparer = prepareSources {
    if (trackJourney) {
      _listeningTracker = ListeningTracker(
        onListen: (verse) {
          unawaited(JourneyStore.recordListen(verse));
          unawaited(ReadingProgressStore.recordReadingActivity());
        },
        onSeconds: (seconds) =>
            unawaited(JourneyStore.recordTime(listening: seconds)),
      );
      _player.positionStream.listen((_) => _trackListening());
    }
    _player.currentIndexStream.listen((index) {
      if (!_preparing &&
          !_reloadingRepeat &&
          _sessionActive &&
          index != null &&
          index >= 0 &&
          index < _playbackVerses.length) {
        _currentPlaybackIndex = index;
      }
      notifyListeners();
    });
    _player.playerStateStream.listen((state) {
      _trackListening();
      if (!_preparing && !_reloadingRepeat && _sessionActive) {
        if (state.processingState == ProcessingState.completed) {
          _handleCompletedPlayback();
        } else {
          // Also honour pause/play from the lock screen and audio interruptions.
          _playWhenReady = state.playing;
        }
      }
      notifyListeners();
    });
    _player.errorStream.listen((error) {
      debugPrint('[AUDIO] Playback source error: $error');
      _sessionActive = false;
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
  }) => QuranAudioController._(
    player: player,
    prepareSources: prepareSources,
    trackJourney: false,
  );

  ListeningTracker? _listeningTracker;
  void _trackListening() {
    final tracker = _listeningTracker;
    if (tracker == null) return;
    final surah = currentSurah;
    final ayah = currentAyah;
    if (surah == null || ayah == null || _preparing || _reloadingRepeat) return;
    tracker.sample(
      occurrence: '$_playRequestId:$_rangeCycle:$_currentPlaybackIndex',
      verse: '$surah:$ayah',
      position: _player.position,
      duration: _player.duration,
      playing:
          _player.playing && _player.processingState == ProcessingState.ready,
    );
  }

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
  bool _sessionActive = false;
  List<AudioVerse> _playbackVerses = const [];
  List<AudioSource> _cycleSources = const [];
  int _currentPlaybackIndex = 0;
  bool _reloadingRepeat = false;
  bool _playWhenReady = false;
  int _rangeCycle = 1;
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
  bool get playing =>
      _sessionActive && (_reloadingRepeat ? _playWhenReady : _player.playing);

  /// Remains active while paused, buffering or loading another repeat.
  bool get hasActivePlayback => _sessionActive;
  int get playbackSessionId => _playRequestId;
  ProcessingState get processingState => _player.processingState;
  bool get hasPlan => _plan != null;

  int? get currentIndex => _player.currentIndex;
  int get totalItems => _player.sequence.length;

  MediaItem? get currentMediaItem {
    final tag = _player.sequenceState.currentSource?.tag;
    return tag is MediaItem ? tag : null;
  }

  AudioVerse? get currentVerse => _sessionActive && _playbackVerses.isNotEmpty
      ? _playbackVerses[_currentPlaybackIndex]
      : null;
  int? get currentSurah => currentVerse?.surah;
  int? get currentAyah => currentVerse?.ayah;
  int? get currentRepeat {
    if (_plan?.repeatMode == AudioRepeatMode.range) return _rangeCycle;
    return currentVerse?.cycle;
  }

  Future<void> playPlan(AudioPlaybackPlan plan) async {
    _listeningTracker?.reset();
    final requestId = ++_playRequestId;
    _downloadCancelToken?.cancel('Replaced by another audio request');
    final cancelToken = CancelToken();
    _downloadCancelToken = cancelToken;

    _preparing = true;
    _sessionActive = false;
    _playbackVerses = _playbackVersesForPlayer(plan);
    _currentPlaybackIndex = 0;
    _error = null;
    _errorKind = QuranAudioErrorKind.none;
    _downloadState = const AudioDownloadState.idle();
    _plan = plan;
    _rangeCycle = 1;
    _reloadingRepeat = false;
    _playWhenReady = true;
    notifyListeners();

    try {
      await _player.stop();
      _throwIfStale(requestId);

      final localSources =
          await (_sourcePreparer?.call(plan) ??
              _prepareSources(plan, requestId, cancelToken));
      _throwIfStale(requestId);
      _cycleSources = List.unmodifiable(localSources);

      await _player.setAudioSources(
        List.of(_cycleSources),
        initialIndex: 0,
        initialPosition: Duration.zero,
      );
      _throwIfStale(requestId);

      // Repeat through a freshly loaded queue, never reuse an ended native queue.
      await _player.setLoopMode(LoopMode.off);
      _throwIfStale(requestId);

      _startPlayback(requestId);
    } on DioException catch (e) {
      if (!_isCurrentRequest(requestId) || CancelToken.isCancel(e)) return;
      _sessionActive = false;
      _errorKind = QuranAudioErrorKind.connectionRequired;
      _error =
          'Connection needed to download this audio the first time. Once downloaded, it will play offline.';
    } on _StaleAudioRequest {
      return;
    } catch (e) {
      if (!_isCurrentRequest(requestId)) return;
      _errorKind = QuranAudioErrorKind.playback;
      _sessionActive = false;
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
    if (!_isCurrentRequest(requestId)) return;
    _sessionActive = true;
    unawaited(
      _player.play().catchError((Object error) {
        if (!_isCurrentRequest(requestId)) return;
        _sessionActive = false;
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

  void _handleCompletedPlayback() {
    final plan = _plan;
    if (plan == null || _preparing || !_sessionActive || _reloadingRepeat) {
      return;
    }
    final hasAnotherCycle =
        plan.infiniteRepeat ||
        (plan.repeatMode == AudioRepeatMode.range &&
            _rangeCycle < plan.visibleRepeatCount);
    if (hasAnotherCycle) {
      // Set the guard synchronously: pause() can emit another completed event.
      _reloadingRepeat = true;
      unawaited(_loadNextRepeat(_playRequestId));
    } else {
      _sessionActive = false;
      _playWhenReady = false;
      // just_audio retains playing=true at EOF. Reset it explicitly so a later
      // play request reaches both the background handler and the native player.
      unawaited(_player.pause());
    }
  }

  Future<void> _loadNextRepeat(int requestId) async {
    try {
      // Seeking the already-ended AVQueuePlayer can reuse exhausted items.
      // Pause first, then load() rebuilds its native items from the source
      // definitions. Reuse those definitions: just_audio retains registered Dart
      // sources until disposal, so allocating more on every loop would grow it.
      await _player.pause().timeout(const Duration(seconds: 10));
      _throwIfStale(requestId);
      final nextCycle = _rangeCycle + 1;
      await _player
          .setAudioSources(
            List.of(_cycleSources),
            initialIndex: 0,
            initialPosition: Duration.zero,
          )
          .timeout(const Duration(seconds: 20));
      _throwIfStale(requestId);
      if (_player.processingState == ProcessingState.completed ||
          _player.processingState == ProcessingState.idle) {
        throw StateError('The repeated audio did not become ready');
      }
      _currentPlaybackIndex = 0;
      _rangeCycle = nextCycle;
      _reloadingRepeat = false;
      if (_playWhenReady) _startPlayback(requestId);
    } on _StaleAudioRequest {
      return;
    } catch (error) {
      if (!_isCurrentRequest(requestId)) return;
      debugPrint('[AUDIO] Repeat load failed: $error');
      _sessionActive = false;
      _playWhenReady = false;
      _errorKind = QuranAudioErrorKind.playback;
      _error = 'Could not repeat audio. Please try again.';
      await _player.stop();
    } finally {
      if (_isCurrentRequest(requestId)) {
        _reloadingRepeat = false;
        notifyListeners();
      }
    }
  }

  Future<void> togglePlayPause() async {
    if (_preparing) return;
    if (_reloadingRepeat) {
      // A pause during the reload must not be undone by its eventual completion.
      _playWhenReady = !_playWhenReady;
      notifyListeners();
      return;
    }
    if (playing) {
      _playWhenReady = false;
      await _player.pause();
      return;
    }
    if (!_sessionActive) {
      final plan = _plan;
      if (plan != null) await playPlan(plan);
      return;
    }
    _playWhenReady = true;
    _startPlayback(_playRequestId);
    notifyListeners();
  }

  Future<void> stop() async {
    _sessionActive = false;
    _playWhenReady = false;
    _listeningTracker?.reset();
    ++_playRequestId;
    _downloadCancelToken?.cancel('Playback stopped');
    _downloadCancelToken = null;
    _preparing = false;
    _reloadingRepeat = false;
    await _player.stop();
    _downloadState = const AudioDownloadState.idle();
    notifyListeners();
  }

  Future<void> seekNext() async {
    if (_preparing || _reloadingRepeat || !_sessionActive) return;
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  Future<void> seekPrevious() async {
    if (_preparing || _reloadingRepeat || !_sessionActive) return;
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
    return _createSources(plan, requestId);
  }

  Future<List<AudioSource>> _createSources(
    AudioPlaybackPlan plan,
    int requestId,
  ) async {
    final artworkUri = await _audioArtworkUri();
    _throwIfStale(requestId);
    return [
      for (final verse in _playbackVersesForPlayer(plan))
        AudioSource.file(
          await _pathFor(plan.reciter, verse.surah, verse.ayah),
          tag: MediaItem(
            id: '$requestId-${plan.reciter.id}-${verse.surah}-${verse.ayah}-${verse.cycle}',
            album: plan.sourceMode == AudioSourceMode.playlist
                ? 'Your surah queue'
                : plan.surahInfo.name,
            artist: plan.reciter.name,
            artUri: artworkUri,
            title:
                '${quranSurahs[verse.surah - 1].name} ${verse.surah}:${verse.ayah}'
                '${plan.repeatMode == AudioRepeatMode.ayah ? ' (${verse.cycle}/${plan.repeatLabel})' : ''}',
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
      _artworkUri = await prepareAudioArtwork(dir);
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
