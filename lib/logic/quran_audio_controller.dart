import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/quran_audio.dart';
import '../progress/journey_store.dart';
import '../progress/journey_tracking.dart';
import '../progress/reading_progress_store.dart';
import '../utils/audio_artwork.dart';
import 'audio_repository.dart';

enum QuranAudioErrorKind { none, connectionRequired, playback }

class AudioDownloadState {
  const AudioDownloadState({
    required this.active,
    required this.completed,
    required this.total,
    required this.message,
    this.fraction,
  });
  const AudioDownloadState.idle()
    : active = false,
      completed = 0,
      total = 0,
      message = '',
      fraction = null;
  final bool active;
  final int completed, total;
  final String message;
  final double? fraction;
  double? get progress => fraction ?? (total == 0 ? null : completed / total);
}

/// The sole authority for playback intent, cursor, repeats and recovery. The
/// audio_service handler and UI issue exactly the same commands to this object.
class QuranAudioController extends ChangeNotifier {
  QuranAudioController._({
    AudioPlayer? player,
    AudioRecordingRepository? repository,
    bool trackJourney = true,
    this.retryDelay = const Duration(seconds: 1),
    this.loadTimeout = const Duration(seconds: 20),
    Future<List<AudioSource>> Function(AudioPlaybackPlan)? prepareSources,
  }) : _player =
           player ??
           AudioPlayer(
             maxSkipsOnError: 0,
             handleInterruptions: false,
             handleAudioSessionActivation: true,
           ),
       _repository = repository ?? AudioRepository(),
       _legacyPreparer = prepareSources {
    if (trackJourney) {
      _tracker = ListeningTracker(
        onListen: (verse) {
          unawaited(JourneyStore.recordListen(verse));
          unawaited(ReadingProgressStore.recordReadingActivity());
        },
        onSeconds: (seconds) =>
            unawaited(JourneyStore.recordTime(listening: seconds)),
      );
      _subscriptions.add(
        _player.positionStream.listen((_) => _trackListening()),
      );
    }
    _subscriptions.add(_player.playerStateStream.listen(_nativeState));
    _subscriptions.add(
      _player.errorStream.listen((error) {
        if (_active && !_loading && phase != QuranPlaybackPhase.failed) {
          unawaited(_recoverDecoder());
        }
      }),
    );
  }

  static final instance = QuranAudioController._();
  @visibleForTesting
  factory QuranAudioController.forTesting({
    required AudioPlayer player,
    Future<List<AudioSource>> Function(AudioPlaybackPlan)? prepareSources,
    AudioRecordingRepository? repository,
    Duration retryDelay = Duration.zero,
    Duration loadTimeout = const Duration(seconds: 20),
  }) => QuranAudioController._(
    player: player,
    repository: repository,
    prepareSources: prepareSources,
    trackJourney: false,
    retryDelay: retryDelay,
    loadTimeout: loadTimeout,
  );

  final AudioPlayer _player;
  final AudioRecordingRepository _repository;
  final Future<List<AudioSource>> Function(AudioPlaybackPlan)? _legacyPreparer;
  final Duration retryDelay, loadTimeout;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _sources = <String, AudioSource>{};
  ListeningTracker? _tracker;
  AudioPlaybackPlan? _plan;
  QuranPlaybackCursor? _cursor;
  QuranPlaybackPhase _phase = QuranPlaybackPhase.idle;
  QuranPlaybackPhase get phase => _phase;
  AudioFailure? failure;
  String? _error;
  AudioDownloadState _download = const AudioDownloadState.idle();
  AudioDownloadState _offlineDownload = const AudioDownloadState.idle();
  bool _active = false, _intent = false, _loading = false, _ready = false;
  int _session = 0, _operation = 0;
  int recoveryAttempt = 0;
  CancelToken _token = CancelToken();
  CancelToken? _offlineToken;
  Future<void> _nativeTail = Future.value();
  Duration _savedPosition = Duration.zero;
  Uri? _artwork;
  MediaItem? _media;
  // Recovery and seeks retain occurrence identity, preventing duplicate stats.
  int _occurrence = 0;
  int _decoderRecoveries = 0;
  bool _begun = false;
  bool _disposed = false;
  Timer? _stallTimer;

  AudioPlayer get player => _player;
  AudioPlaybackPlan? get plan => _plan;
  AudioDownloadState get downloadState =>
      _download.active ? _download : _offlineDownload;
  bool get offlineDownloading => _offlineDownload.active;
  String? get error => _error;
  QuranAudioErrorKind get errorKind => failure == null
      ? QuranAudioErrorKind.none
      : failure!.kind == AudioFailureKind.connectivity
      ? QuranAudioErrorKind.connectionRequired
      : QuranAudioErrorKind.playback;
  bool get preparing => phase == QuranPlaybackPhase.preparing;
  bool get playing => _active && _intent && phase != QuranPlaybackPhase.failed;
  bool get audible => phase == QuranPlaybackPhase.playing && _ready;
  bool get hasActivePlayback => _active;
  bool get hasPlan => _plan != null;
  int get playbackSessionId => _session;
  ProcessingState get processingState => _player.processingState;
  int? get currentIndex => _cursor?.index;
  int get totalItems => _cursor?.verses.length ?? 0;
  MediaItem? get currentMediaItem => _media;
  QuranAudioItem? get currentItem => _active ? _cursor?.item : null;
  bool get isIntroduction => currentItem?.isIntroduction ?? false;
  AudioVerse? get currentVerse {
    final item = currentItem;
    if (!_begun || item == null || item.isIntroduction) return null;
    return AudioVerse(
      surah: item.surah,
      ayah: item.ayah!,
      cycle: currentRepeat ?? 1,
    );
  }

  int? get currentSurah => currentItem?.surah;
  int? get currentAyah => currentVerse?.ayah;
  int? get currentRepeat => _active ? _cursor?.repetition : null;
  String get statusLabel => switch (phase) {
    QuranPlaybackPhase.preparing =>
      _download.active ? 'Downloading' : 'Preparing',
    QuranPlaybackPhase.buffering =>
      _download.active ? 'Downloading' : 'Buffering',
    QuranPlaybackPhase.recovering => 'Recovering · attempt $recoveryAttempt/3',
    QuranPlaybackPhase.failed => 'Needs attention',
    QuranPlaybackPhase.paused => 'Paused',
    QuranPlaybackPhase.completed => 'Completed',
    QuranPlaybackPhase.playing => 'Playing',
    QuranPlaybackPhase.idle => 'Stopped',
  };

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int session, int operation) =>
      _active &&
      session == _session &&
      operation == _operation &&
      !_token.isCancelled;

  Future<void> _native(Future<void> Function() action) {
    final next = _nativeTail.then((_) => action());
    _nativeTail = next.catchError((Object _) {});
    return next;
  }

  void _nativeState(PlayerState state) {
    if (!_active ||
        _loading ||
        !_ready ||
        phase == QuranPlaybackPhase.failed ||
        state.processingState != _player.processingState ||
        state.playing != _player.playing) {
      return;
    }
    _trackListening();
    if (state.processingState == ProcessingState.completed) {
      // Synchronous guard rejects duplicate EOF events while the next item loads.
      _loading = true;
      final session = _session, operation = _operation;
      scheduleMicrotask(() {
        if (_valid(session, operation)) unawaited(_completed());
      });
    } else if (state.processingState == ProcessingState.buffering ||
        state.processingState == ProcessingState.loading) {
      _phase = _intent
          ? QuranPlaybackPhase.buffering
          : QuranPlaybackPhase.paused;
      if (_intent && !(_stallTimer?.isActive ?? false)) {
        final session = _session, operation = _operation;
        _stallTimer = Timer(const Duration(seconds: 30), () {
          if (_valid(session, operation) && _intent) {
            unawaited(_recoverDecoder());
          }
        });
      }
      _publish();
    } else if (state.processingState == ProcessingState.ready) {
      _stallTimer?.cancel();
      if (!state.playing) _intent = false;
      _phase = _intent && state.playing
          ? QuranPlaybackPhase.playing
          : QuranPlaybackPhase.paused;
      _publish();
    } else if (state.processingState == ProcessingState.idle && _intent) {
      unawaited(_recoverDecoder());
    }
  }

  void _trackListening() {
    final item = currentItem;
    if (item == null || !_begun) return;
    _tracker?.sample(
      occurrence: '$_session:$_occurrence',
      verse: item.ayah == null ? '' : '${item.surah}:${item.ayah}',
      countVerse: !item.isIntroduction,
      position: _player.position,
      duration: _player.duration,
      playing: audible && _player.playing,
    );
  }

  Future<void> playPlan(AudioPlaybackPlan plan) async {
    _token.cancel('Replaced playback');
    _token = CancelToken();
    _session++;
    _operation++;
    _tracker?.reset();
    _plan = plan;
    _cursor = QuranPlaybackCursor(plan);
    _cursor!.introduction = _cursor!.needsIntroduction;
    _sources.clear();
    _active = true;
    _intent = true;
    _ready = false;
    _loading = true;
    _occurrence = 0;
    _decoderRecoveries = 0;
    _begun = false;
    _stallTimer?.cancel();
    _error = null;
    failure = null;
    _media = null;
    _savedPosition = Duration.zero;
    _phase = QuranPlaybackPhase.preparing;
    _publish();
    // stop cancels a pending native source load before the new serialized load.
    final session = _session;
    await _player.stop();
    if (!_active || session != _session || _token.isCancelled) return;
    await _prepareCurrent();
  }

  Future<void> _prepareCurrent({bool decoderFailure = false}) async {
    final session = _session, operation = ++_operation;
    final token = _token, plan = _plan!, item = _cursor!.item;
    var position = _savedPosition;
    _loading = true;
    _stallTimer?.cancel();
    _ready = false;
    _media = MediaItem(
      id: '$session:${item.key}',
      title: item.label,
      artist: plan.reciter.name,
      artUri: _artwork,
    );
    failure = null;
    _error = null;
    _phase = decoderFailure
        ? QuranPlaybackPhase.recovering
        : _occurrence > 0
        ? QuranPlaybackPhase.buffering
        : QuranPlaybackPhase.preparing;
    _publish();
    for (
      var attempt = 0;
      attempt <= 3 && _valid(session, operation);
      attempt++
    ) {
      try {
        if (attempt > 0) {
          recoveryAttempt = attempt;
          _phase = QuranPlaybackPhase.recovering;
          _publish();
          await Future.any([
            Future<void>.delayed(retryDelay * (1 << (attempt - 1))),
            token.whenCancel.then<void>((_) {}),
          ]);
          if (!_valid(session, operation)) return;
        }
        if (decoderFailure) {
          await _repository.invalidate(plan.reciter, item);
          if (!_valid(session, operation)) return;
          _sources.remove(item.key);
          decoderFailure = false;
        }
        AudioSource source;
        if (_legacyPreparer != null) {
          final sources = await _legacyPreparer(plan);
          if (sources.isEmpty) {
            throw StateError('Test source preparer returned no recording');
          }
          source = sources[_cursor!.index.clamp(0, sources.length - 1)];
        } else {
          final path = await _repository.recording(
            plan.reciter,
            item,
            token,
            onProgress: (value) {
              if (!_valid(session, operation)) return;
              _download = AudioDownloadState(
                active: true,
                completed: 0,
                total: 1,
                message: 'Downloading ${item.label}',
                fraction: value,
              );
              _publish();
            },
          );
          if (!_valid(session, operation)) return;
          source = _sources.putIfAbsent(item.key, () => AudioSource.file(path));
        }
        if (!_valid(session, operation)) return;
        var nativeFailure = false;
        await _native(() async {
          if (!_valid(session, operation)) return;
          try {
            // Preserve the v4 iOS workaround: pause, then reload source definitions
            // instead of seeking an exhausted AVQueuePlayer. Reuse definitions.
            await _player.pause().timeout(loadTimeout);
            if (!_valid(session, operation)) return;
            await _player
                .setAudioSources(
                  [source],
                  initialIndex: 0,
                  initialPosition: position,
                )
                .timeout(loadTimeout);
            if (!_valid(session, operation)) return;
            await _player.setLoopMode(LoopMode.off);
            if (_player.processingState == ProcessingState.idle ||
                _player.processingState == ProcessingState.completed ||
                _player.duration == Duration.zero) {
              throw StateError('Recording did not become usable');
            }
          } catch (_) {
            nativeFailure = true;
            // Interrupt native work on timeout before releasing the command lane.
            await _player.stop();
            rethrow;
          }
        }).catchError((Object e) {
          if (nativeFailure) {
            throw const AudioFailure(
              AudioFailureKind.decoder,
              'The audio decoder could not play this recording.',
            );
          }
          throw e;
        });
        if (!_valid(session, operation)) return;
        _download = const AudioDownloadState.idle();
        _loading = false;
        _ready = true;
        _savedPosition = Duration.zero;
        recoveryAttempt = 0;
        _media = MediaItem(
          id: '$_session:${item.key}',
          title: item.label,
          album: 'Quran recitation',
          artist: plan.reciter.name,
          artUri: _artwork,
          duration: _player.duration,
          extras: {
            'surah': item.surah,
            if (item.ayah != null) 'ayah': item.ayah!,
            'introduction': item.isIntroduction,
            'repeat': currentRepeat ?? 1,
          },
        );
        _phase = _intent
            ? QuranPlaybackPhase.playing
            : QuranPlaybackPhase.paused;
        _publish();
        if (_intent) _startNative(session, operation);
        _prefetch(session);
        return;
      } catch (e) {
        if (!_valid(session, operation) ||
            (e is DioException && CancelToken.isCancel(e))) {
          return;
        }
        final problem = e is AudioFailure
            ? e
            : const AudioFailure(
                AudioFailureKind.decoder,
                'Could not load the recording.',
              );
        if (problem.kind == AudioFailureKind.decoder &&
            position > Duration.zero) {
          position = Duration.zero;
        }
        decoderFailure =
            problem.kind == AudioFailureKind.decoder ||
            problem.kind == AudioFailureKind.corrupt;
        if (!problem.recoverable || attempt == 3) {
          failure = problem;
          _error = '${item.label}: ${problem.message}';
          _phase = QuranPlaybackPhase.failed;
          _loading = false;
          _download = const AudioDownloadState.idle();
          _publish();
          return;
        }
      }
    }
  }

  void _startNative(int session, int operation) {
    if (!_valid(session, operation) || !_intent || !_ready) return;
    _begun = true;
    // play() resolves at EOF, so never await it inside the command lane.
    unawaited(
      _player.play().catchError((Object _) {
        if (_valid(session, operation) && !_loading) {
          unawaited(_recoverDecoder());
        }
      }),
    );
  }

  Future<void> _recoverDecoder() async {
    if (!_active || _loading) return;
    if (_decoderRecoveries++ >= 3) {
      failure = const AudioFailure(
        AudioFailureKind.decoder,
        'The decoder repeatedly failed. Retry this recording, skip it, or stop.',
      );
      _error = '${currentItem?.label}: ${failure!.message}';
      _phase = QuranPlaybackPhase.failed;
      _ready = false;
      _stallTimer?.cancel();
      _publish();
      await _player.pause();
      return;
    }
    _loading = true;
    _trackListening();
    _savedPosition = _player.position;
    await _prepareCurrent(decoderFailure: true);
  }

  Future<void> _completed() async {
    if (!_active) return;
    _tracker?.flush();
    if (!_cursor!.advance()) {
      _active = false;
      _intent = false;
      _loading = false;
      _ready = false;
      _phase = QuranPlaybackPhase.completed;
      await _player.pause();
      _publish();
      return;
    }
    _occurrence++;
    _begun = false;
    _decoderRecoveries = 0;
    _savedPosition = Duration.zero;
    await _prepareCurrent();
  }

  void _prefetch(int session) {
    if (_legacyPreparer != null) return;
    final cursor = _cursor!, plan = _plan!, token = _token;
    // At most three future DISTINCT ayahs, plus introductions on their boundary.
    final items = <QuranAudioItem>[];
    var i = cursor.index + (cursor.introduction ? 0 : 1);
    for (var n = 0; n < 3 && n < cursor.verses.length; n++, i++) {
      if (i >= cursor.verses.length) {
        if (plan.repeatMode != AudioRepeatMode.range ||
            (!plan.infiniteRepeat &&
                cursor.rangeCycle >= plan.visibleRepeatCount)) {
          break;
        }
        i = 0;
      }
      final verse = cursor.verses[i];
      if (verse.ayah == 1 &&
          verse.surah != 1 &&
          verse.surah != 9 &&
          !(cursor.introduction && i == cursor.index)) {
        items.add(QuranAudioItem(surah: verse.surah));
      }
      items.add(QuranAudioItem(surah: verse.surah, ayah: verse.ayah));
    }
    for (final item in items) {
      if (session != _session || token.isCancelled) return;
      unawaited(
        _repository
            .recording(plan.reciter, item, token, urgent: false)
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  Future<void> play() async {
    if (!_active) {
      if (_plan != null) await playPlan(_plan!);
      return;
    }
    _intent = true;
    if (phase == QuranPlaybackPhase.failed) {
      await retry();
      return;
    }
    if (_ready && !_loading) {
      _phase = QuranPlaybackPhase.playing;
      _startNative(_session, _operation);
    }
    _publish();
  }

  Future<void> pause() async {
    _intent = false;
    _stallTimer?.cancel();
    if (_ready) _phase = QuranPlaybackPhase.paused;
    _trackListening();
    _publish();
    await _player.pause();
  }

  Future<void> togglePlayPause() => playing ? pause() : play();
  Future<void> retry() async {
    if (!_active || phase != QuranPlaybackPhase.failed) return;
    _decoderRecoveries = 0;
    await _prepareCurrent(
      decoderFailure: failure?.kind == AudioFailureKind.decoder,
    );
  }

  void clearError() {
    // Keep unresolved failures accessible even if older callers dismiss a dialog.
    if (phase == QuranPlaybackPhase.failed) return;
    _error = null;
    failure = null;
    _publish();
  }

  Future<void> stop() async {
    _session++;
    _operation++;
    _stallTimer?.cancel();
    _token.cancel('Playback stopped');
    _active = _intent = _ready = _loading = false;
    _tracker?.reset();
    _error = null;
    failure = null;
    _media = null;
    _phase = QuranPlaybackPhase.idle;
    _download = const AudioDownloadState.idle();
    _publish();
    await _player.stop();
  }

  Future<void> seekNext() async {
    if (!_active) return;
    final session = _session, operation = ++_operation;
    _loading = true;
    await _player.stop();
    if (!_valid(session, operation)) return;
    if (!_cursor!.advance(manual: true)) {
      await stop();
      return;
    }
    _occurrence++;
    _begun = false;
    _decoderRecoveries = 0;
    _savedPosition = Duration.zero;
    await _prepareCurrent();
  }

  Future<void> seekPrevious() async {
    if (!_active) return;
    final session = _session, operation = ++_operation;
    _loading = true;
    await _player.stop();
    if (!_valid(session, operation)) return;
    _cursor!.previous();
    _occurrence++;
    _begun = false;
    _decoderRecoveries = 0;
    _savedPosition = Duration.zero;
    await _prepareCurrent();
  }

  Future<void> seek(Duration position) async {
    if (!_active || !_ready || _loading) return;
    await _player.seek(position);
    _trackListening();
    _publish();
  }

  Future<void> downloadSelection(AudioPlaybackPlan selection) async {
    _offlineToken?.cancel('New offline selection');
    final token = _offlineToken = CancelToken();
    final items = <String, QuranAudioItem>{};
    for (final verse in selection.uniqueVerses()) {
      if (verse.ayah == 1 && verse.surah != 1 && verse.surah != 9) {
        final intro = QuranAudioItem(surah: verse.surah);
        items[intro.key] = intro;
      }
      final item = QuranAudioItem(surah: verse.surah, ayah: verse.ayah);
      items[item.key] = item;
    }
    var done = 0;
    var unverifiedIntroductions = 0;
    String? currentLabel;
    try {
      for (final item in items.values) {
        currentLabel = item.label;
        if (token.isCancelled) throw token.cancelError!;
        _offlineDownload = AudioDownloadState(
          active: true,
          completed: done,
          total: items.length,
          message: 'Downloading ${item.label}',
        );
        _publish();
        try {
          await _repository.recording(
            selection.reciter,
            item,
            token,
            urgent: false,
          );
        } on AudioFailure catch (e) {
          if (!item.isIntroduction || e.kind != AudioFailureKind.unavailable) {
            rethrow;
          }
          // Offline downloads can retain every numbered ayah. Playback still
          // requires the user's explicit choice at each unavailable introduction.
          unverifiedIntroductions++;
        }
        done++;
      }
      if (_offlineToken == token) {
        _offlineDownload = AudioDownloadState(
          active: false,
          completed: done,
          total: items.length,
          message: unverifiedIntroductions == 0
              ? 'Selection available offline'
              : 'Ayahs available offline. Separate Bismillah is unverified for '
                    '$unverifiedIntroductions surah(s); playback will ask before continuing.',
        );
      }
    } catch (e) {
      if (!token.isCancelled && _offlineToken == token) {
        _offlineDownload = AudioDownloadState(
          active: false,
          completed: done,
          total: items.length,
          message: 'Download stopped at $currentLabel: $e',
        );
      }
    }
    _publish();
  }

  void cancelDownload() {
    _offlineToken?.cancel('Cancelled offline download');
    _offlineDownload = const AudioDownloadState.idle();
    _publish();
  }

  Future<void> prepareArtwork() async {
    try {
      _artwork = await prepareAudioArtwork(
        await getApplicationSupportDirectory(),
      );
    } catch (_) {
      /* Playback remains available without artwork. */
    }
  }

  static String audioId(int surah, int ayah) =>
      AudioRepository.audioId(surah, ayah);

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _stallTimer?.cancel();
    _token.cancel();
    _offlineToken?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _tracker?.reset();
    unawaited(_player.dispose());
    super.dispose();
  }
}
