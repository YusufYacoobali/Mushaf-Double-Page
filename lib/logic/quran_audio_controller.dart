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
import '../utils/bismillah_sources.dart';
import 'audio_repository.dart';
import 'audio_playback_backend.dart';
import '../models/everyayah_pcm_proof.dart';

part 'quran_audio_pcm_proof.dart';

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

class _QueueEntry {
  _QueueEntry(this.occurrence) : primarySource = occurrence.item.source;
  QuranAudioOccurrence occurrence;
  final AudioRecordingSource? primarySource;
  AudioSource? source;
  Future<String>? preparation;
  AudioFailure? failure;
  String? path;
  bool urgentPreparation = false;
  bool retriedRenderedPosition = false;
  bool invertRightChannel = false;
  int attempts = 0, decoderRestarts = 0, alternative = 0;
  QuranPlaybackCursor get cursor => occurrence.cursor;
  QuranAudioItem get item => occurrence.item;
}

/// One authoritative cursor, adopted from actual native source transitions.
/// The planning tail contains cursor copies, never a second active playhead.
class QuranAudioController extends ChangeNotifier {
  QuranAudioController._({
    AudioPlayer? player,
    AudioPlaybackBackend? continuousBackend,
    AudioPlaybackBackend Function()? continuousBackendFactory,
    AudioRecordingRepository? repository,
    bool trackJourney = true,
    ListeningTracker? listeningTracker,
    this.retryDelay = const Duration(seconds: 1),
    this.stallTimeout = const Duration(seconds: 30),
    this.loadTimeout = const Duration(seconds: 20),
    this.resolveIntroduction = BismillahSources.resolve,
    Future<List<AudioSource>> Function(AudioPlaybackPlan)? prepareSources,
  }) : _player =
           player ??
           AudioPlayer(
             maxSkipsOnError: 0,
             handleInterruptions: false,
             handleAudioSessionActivation: true,
           ),
       _repository = repository ?? AudioRepository(),
       _legacyPreparer = prepareSources,
       _continuousFactory =
           continuousBackendFactory ??
           (continuousBackend != null
               ? (() => continuousBackend)
               : player == null && ContinuousPcmBackend.supported
               ? (() => ContinuousPcmBackend())
               : null) {
    _tracker = listeningTracker;
    if (trackJourney) {
      _tracker = ListeningTracker(
        onListen: (verse) {
          unawaited(JourneyStore.recordListen(verse));
          unawaited(ReadingProgressStore.recordReadingActivity());
        },
        onSeconds: (seconds) =>
            unawaited(JourneyStore.recordTime(listening: seconds)),
      );
    }
    _legacyBackend = JustAudioBackend(_player);
    _bindBackend(_legacyBackend);
  }

  void _bindBackend(AudioPlaybackBackend backend) {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _backend = backend;
    _subscriptions.add(
      backend.positionStream.listen((_) {
        if (!identical(_backend, backend)) return;
        if (_pcmActive) _pcmPositionChanged();
        _trackListening();
      }),
    );
    _subscriptions.add(
      backend.sequenceStateStream.listen((state) {
        if (identical(_backend, backend)) _sequenceChanged(state);
      }),
    );
    _subscriptions.add(
      backend.playerStateStream.listen((state) {
        if (identical(_backend, backend)) _nativeState(state);
      }),
    );
    _subscriptions.add(
      backend.errorStream.listen((error) {
        if (identical(_backend, backend)) _nativeError(error);
      }),
    );
  }

  static final instance = QuranAudioController._();
  @visibleForTesting
  factory QuranAudioController.forTesting({
    required AudioPlayer player,
    AudioPlaybackBackend? continuousBackend,
    AudioPlaybackBackend Function()? continuousBackendFactory,
    AudioRecordingRepository? repository,
    Future<List<AudioSource>> Function(AudioPlaybackPlan)? prepareSources,
    BismillahResolver resolveIntroduction = BismillahSources.resolve,
    ListeningTracker? listeningTracker,
    Duration retryDelay = Duration.zero,
    Duration stallTimeout = const Duration(seconds: 30),
    Duration loadTimeout = const Duration(seconds: 20),
  }) => QuranAudioController._(
    player: player,
    continuousBackend: continuousBackend,
    continuousBackendFactory: continuousBackendFactory,
    repository: repository,
    prepareSources: prepareSources,
    trackJourney: false,
    listeningTracker: listeningTracker,
    resolveIntroduction: resolveIntroduction,
    retryDelay: retryDelay,
    loadTimeout: loadTimeout,
    stallTimeout: stallTimeout,
  );

  static const nativeQueueLimit = 6;
  static const forwardWindow = 3;
  EveryAyahPcmProof? _pcmProof;
  bool _pcmActive = false, _pcmLoaded = false;
  int _pcmNavigation = 0;
  PcmProofOccurrence? _pcmRow;
  bool get usingPcmProof => _pcmActive;

  /// Explicit Stage-A target only. Regular main and release builds never opt in.
  void registerPcmProofForDevelopment(EveryAyahPcmProof proof) {
    if (kReleaseMode || _active) throw StateError('Cannot register PCM proof');
    _pcmProof = proof;
  }

  final AudioPlayer _player;
  late final JustAudioBackend _legacyBackend;
  late AudioPlaybackBackend _backend;
  final AudioPlaybackBackend Function()? _continuousFactory;
  bool _continuousHandoff = false;
  AudioPlaybackBackend? _retiringBackend;
  String? continuousFallbackReason;
  bool get usingContinuousPcm => !identical(_backend, _legacyBackend);
  String get activeBackend =>
      usingContinuousPcm ? 'continuous-pcm' : 'just_audio';
  final AudioRecordingRepository _repository;
  final BismillahResolver resolveIntroduction;
  final Duration retryDelay, loadTimeout, stallTimeout;
  final Future<List<AudioSource>> Function(AudioPlaybackPlan)? _legacyPreparer;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _queue = <_QueueEntry>[];
  final _pending = <_QueueEntry>[];
  final _omittedIntroductions = <String>{};
  final _deferredFailures = <String, AudioFailure>{};
  ListeningTracker? _tracker;
  AudioPlaybackPlan? _plan;
  QuranPlaybackCursor? _cursor;
  _QueueEntry? _current, _waiting, _failed;
  AudioFailure? failure;
  String? _error;
  QuranPlaybackPhase _phase = QuranPlaybackPhase.idle;
  AudioDownloadState _download = const AudioDownloadState.idle();
  AudioDownloadState _offlineDownload = const AudioDownloadState.idle();
  bool _active = false, _intent = false, _installing = false, _begun = false;
  bool _exhausted = false, _disposed = false;
  bool _starting = false;
  int _playRequest = 0;
  String? introductionNotice;
  int _session = 0, _revision = 0, _ordinal = 0;
  int _queueReloads = 0;
  int get queueReloadCount => _queueReloads;
  int? _fillRevision;
  int recoveryAttempt = 0;
  CancelToken _token = CancelToken();
  CancelToken? _offlineToken;
  bool _offlineNeedsRefresh = false;
  Future<void> _nativeTail = Future.value();
  Timer? _stall;
  Uri? _artwork;
  MediaItem? _media;

  AudioPlayer get player => _player;
  AudioPlaybackPlan? get plan => _plan;
  QuranPlaybackPhase get phase => _phase;
  AudioDownloadState get downloadState =>
      _download.active ? _download : _offlineDownload;
  bool get offlineDownloading => _offlineDownload.active;
  String? get error => _error;
  QuranAudioErrorKind get errorKind => failure == null
      ? QuranAudioErrorKind.none
      : failure!.kind == AudioFailureKind.connectivity
      ? QuranAudioErrorKind.connectionRequired
      : QuranAudioErrorKind.playback;
  bool get preparing =>
      phase == QuranPlaybackPhase.preparing ||
      (phase == QuranPlaybackPhase.recovering && _current == null);
  bool get playing => _active && _intent && phase != QuranPlaybackPhase.failed;
  bool get paused => _active && !_intent && phase != QuranPlaybackPhase.failed;
  bool get audible => phase == QuranPlaybackPhase.playing && _begun;
  bool get hasActivePlayback => _active;
  bool get hasPlan => _plan != null;
  int get playbackSessionId => _session;
  ProcessingState get processingState => _backend.processingState;
  Duration get bufferedPlaybackPosition => _pcmActive && _pcmRow != null
      ? _pcmRelative(_backend.bufferedPosition)
      : _backend.bufferedPosition;
  Duration get playbackPosition => _pcmActive && _pcmRow != null
      ? _pcmRelative(_backend.position)
      : _waiting != null && _waiting != _current
      ? Duration.zero
      : _backend.position;
  int? get currentIndex => _cursor?.index;
  int get totalItems => _cursor?.verses.length ?? 0;
  int get nativeQueueLength => _queue.length;
  int get retainedSourceCount => _queue.where((e) => e.source != null).length;
  QuranAudioOccurrence? get currentOccurrence => _current?.occurrence;
  MediaItem? get currentMediaItem => _media;
  _QueueEntry? get _display => _failed ?? _waiting ?? _current;
  QuranAudioItem? get currentItem => _active ? _display?.item : null;
  bool get isIntroduction => currentItem?.isIntroduction ?? false;
  AudioVerse? get currentVerse {
    final item = _current?.item;
    if (!_active ||
        !_begun ||
        _waiting != null ||
        item == null ||
        item.isIntroduction) {
      return null;
    }
    return AudioVerse(
      surah: item.surah,
      ayah: item.ayah!,
      cycle: currentRepeat ?? 1,
    );
  }

  int? get currentSurah => currentItem?.surah;
  int? get currentAyah => currentVerse?.ayah;
  int? get currentRepeat => _active ? _display?.cursor.repetition : null;
  String get statusLabel => switch (phase) {
    QuranPlaybackPhase.preparing =>
      _download.active ? 'Downloading' : 'Preparing',
    QuranPlaybackPhase.buffering => 'Buffering',
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

  bool _valid(int generation, int revision) =>
      _active &&
      !_disposed &&
      generation == _session &&
      revision == _revision &&
      !_token.isCancelled;
  Future<void> _native(Future<void> Function() action) {
    final task = _nativeTail.then((_) => action());
    _nativeTail = task.catchError((Object _) {});
    return task;
  }

  bool _includeIntroduction(int surah) {
    final resolution = resolveIntroduction(_plan!.reciter, surah);
    return resolution.kind == BismillahPolicyKind.separateVerifiedRecording &&
        resolution.source != null &&
        !_omittedIntroductions.contains(resolution.source!.id);
  }

  QuranAudioItem _resolvedItem(Reciter reciter, QuranAudioItem raw) {
    final resolution = resolveIntroduction(reciter, raw.surah);
    final name = '${AudioRepository.audioId(raw.surah, raw.ayah ?? 0)}.mp3';
    return QuranAudioItem(
      surah: raw.surah,
      ayah: raw.ayah,
      source: raw.isIntroduction
          ? resolution.source
          : AudioRecordingSource(
              id: '${reciter.id}/$name',
              cacheFilename: name,
              url: 'https://everyayah.com/data/${reciter.folder}/$name',
              sha256: raw.ayah == 1 ? resolution.openingSha256 : null,
              verification: raw.ayah == 1 && resolution.openingSha256 != null
                  ? resolution.evidence
                  : 'Numbered EveryAyah recording',
            ),
    );
  }

  _QueueEntry _entry(QuranPlaybackCursor cursor) {
    final item = _resolvedItem(_plan!.reciter, cursor.item);
    final entry = _QueueEntry(
      QuranAudioOccurrence(
        occurrenceId: '$_session:${_ordinal++}',
        item: item,
        cursor: cursor.copy(),
        sessionGeneration: _session,
      ),
    );
    entry.failure = _deferredFailures[item.recordingId];
    if (entry.failure != null) entry.attempts = 1;
    return entry;
  }

  _QueueEntry? _next(_QueueEntry entry) {
    final cursor = entry.cursor.copy();
    return cursor.advance() ? _entry(cursor) : null;
  }

  void _adopt(_QueueEntry entry, {required bool begun}) {
    if (_current?.occurrence.occurrenceId != entry.occurrence.occurrenceId) {
      _tracker?.flush();
    }
    _current = entry;
    _cursor = entry.cursor.copy();
    _waiting = _failed = null;
    _begun = begun;
    _exhausted = false;
    failure = null;
    _error = null;
    _metadata(entry);
  }

  void _metadata(_QueueEntry entry) {
    final item = entry.item;
    _media = MediaItem(
      id: entry.occurrence.occurrenceId,
      title: item.label,
      album: 'Quran recitation',
      artist: _plan!.reciter.name,
      artUri: _artwork,
      duration: _backend.duration,
      extras: {
        'surah': item.surah,
        if (item.ayah != null) 'ayah': item.ayah!,
        'introduction': item.isIntroduction,
        'repeat': entry.cursor.repetition,
        'rangeCycle': entry.cursor.rangeCycle,
      },
    );
  }

  void _sequenceChanged(SequenceState state) {
    if (_pcmActive) return;
    if (!_active || _installing) return;
    final tag = state.currentSource?.tag;
    if (tag is! QuranAudioOccurrence || tag.sessionGeneration != _session) {
      return;
    }
    final latest = _backend.sequenceState.currentSource?.tag;
    if (latest is! QuranAudioOccurrence ||
        latest.occurrenceId != tag.occurrenceId) {
      return;
    }
    final entries = {..._queue, ..._pending};
    final entry = entries
        .where((e) => e.occurrence.occurrenceId == tag.occurrenceId)
        .firstOrNull;
    if (entry == null ||
        entry.occurrence.occurrenceId == _current?.occurrence.occurrenceId) {
      return;
    }
    // A late append can allow the OS to resume an exhausted queue itself.
    // Recover its existing occurrence instead of reloading/replaying it.
    if (!_queue.contains(entry)) {
      final mapping = {for (final e in entries) e.occurrence.occurrenceId: e};
      _queue
        ..clear()
        ..addAll(
          state.sequence
              .map((source) => source.tag)
              .whereType<QuranAudioOccurrence>()
              .map((o) => mapping[o.occurrenceId])
              .whereType<_QueueEntry>(),
        );
      _pending.removeWhere(_queue.contains);
    }
    _adopt(entry, begun: _intent && _backend.playing);
    _phase = !_intent
        ? QuranPlaybackPhase.paused
        : _backend.playing
        ? QuranPlaybackPhase.playing
        : QuranPlaybackPhase.buffering;
    _publish();
    _kickFill();
  }

  void _nativeState(PlayerState state) {
    if (_disposed ||
        state.processingState != _backend.processingState ||
        state.playing != _backend.playing) {
      return;
    }
    // Only commands/session interruptions change intent. A late native start
    // must not undo Pause/Stop, even while a source is being installed.
    if (!_intent && state.playing) {
      final generation = _session;
      scheduleMicrotask(() {
        if (!_disposed &&
            generation == _session &&
            !_intent &&
            _backend.playing) {
          unawaited(_backend.pause());
        }
      });
    }
    if (!_active ||
        _installing ||
        phase == QuranPlaybackPhase.failed ||
        _current == null) {
      return;
    }
    if (_pcmActive) _pcmPositionChanged();
    if (!_pcmActive && _media?.duration != _backend.duration) {
      _metadata(_current!);
    }
    _trackListening();
    if (state.processingState == ProcessingState.completed && !_exhausted) {
      _exhausted = true;
      _begun = false;
      final generation = _session, revision = _revision;
      scheduleMicrotask(() {
        if (_valid(generation, revision)) unawaited(_endOfQueue());
      });
    } else if (state.processingState == ProcessingState.buffering ||
        state.processingState == ProcessingState.loading) {
      _phase = !_intent
          ? QuranPlaybackPhase.paused
          : _begun
          ? QuranPlaybackPhase.buffering
          : QuranPlaybackPhase.preparing;
      _watchStall();
      _publish();
    } else if (state.processingState == ProcessingState.ready && !_exhausted) {
      if (!_intent) {
        _phase = QuranPlaybackPhase.paused;
      } else if (state.playing) {
        _stall?.cancel();
        _starting = false;
        _begun = true;
        _phase = QuranPlaybackPhase.playing;
      } else {
        // Ready does not imply that the asynchronous play request has started.
        // In particular, do not turn preparation/background saving into Pause.
        _phase = _begun
            ? QuranPlaybackPhase.buffering
            : QuranPlaybackPhase.preparing;
        _watchStall();
      }
      _publish();
    } else if (state.processingState == ProcessingState.idle &&
        _intent &&
        _current != null &&
        !_exhausted) {
      unawaited(_recoverCurrent(invalidate: false));
    }
  }

  void _watchStall() {
    if (!_intent || (_stall?.isActive ?? false)) return;
    final generation = _session, revision = _revision;
    final entry = _current, backend = _backend;
    final position = backend.position, buffered = backend.bufferedPosition;
    _stall = Timer(stallTimeout, () async {
      bool watching() =>
          _valid(generation, revision) &&
          _active &&
          _intent &&
          !_installing &&
          !_exhausted &&
          identical(backend, _backend);
      if (!watching()) return;
      Object? clockError;
      if (backend is ContinuousPcmBackend) {
        try {
          await backend.refreshClock().timeout(loadTimeout);
        } catch (error) {
          clockError = error;
        }
      }
      if (!watching()) return;
      if (backend.processingState == ProcessingState.ready && backend.playing) {
        return;
      }
      if (_current != entry ||
          backend.position > position ||
          backend.bufferedPosition > buffered) {
        _watchStall();
        return;
      }
      if (clockError != null) {
        await _fallbackContinuous(clockError);
      } else {
        await _recoverCurrent(invalidate: false);
      }
    });
  }

  void _trackListening() {
    if (_pcmActive) {
      _trackPcmListening();
      return;
    }
    final entry = _current;
    if (!_begun || entry == null) return;
    _tracker?.sample(
      occurrence: entry.occurrence.occurrenceId,
      verse: '${entry.item.surah}:${entry.item.ayah}',
      countVerse: !entry.item.isIntroduction,
      position: _backend.position,
      duration: _backend.duration,
      playing: audible && _backend.playing,
    );
  }

  Future<void> playPlan(AudioPlaybackPlan plan) async {
    cancelDownload();
    _cancelWork();
    _pcmActive = false;
    _pcmLoaded = false;
    _pcmRow = null;
    _pcmNavigation = 0;
    _plan = plan;
    _active = true;
    _intent = true;
    introductionNotice = null;
    _omittedIntroductions.clear();
    _deferredFailures.clear();
    _queue.clear();
    _pending.clear();
    _current = _waiting = _failed = null;
    _tracker?.reset();
    _ordinal = 0;
    _queueReloads = 0;
    _begun = false;
    _exhausted = false;
    failure = null;
    _error = null;
    _media = null;
    _phase = QuranPlaybackPhase.preparing;
    if (plan.uniqueVerses().any(
      (v) =>
          v.ayah == 1 &&
          resolveIntroduction(plan.reciter, v.surah).kind ==
              BismillahPolicyKind.unverified,
    )) {
      introductionNotice =
          'Bismillah is unavailable for ${plan.reciter.name}. Playing the selected ayahs.';
    }
    final generation = _session, revision = _revision;
    _publish();
    await _backend.stop();
    if (!_valid(generation, revision)) return;
    if (identical(_backend, _retiringBackend)) {
      await _backend.dispose();
      if (!_valid(generation, revision)) return;
      _bindBackend(_legacyBackend);
    }
    continuousFallbackReason = null;
    if (_pcmProof?.supports(plan) ?? false) {
      if (usingContinuousPcm) {
        final old = _backend;
        _bindBackend(_legacyBackend);
        await old.dispose();
      }
    } else if (!usingContinuousPcm && _continuousFactory != null) {
      _bindBackend(_continuousFactory());
    }
    if (!_valid(generation, revision)) return;
    if (_pcmProof?.supports(plan) ?? false) {
      await _preparePcmProof(generation, revision);
      return;
    }
    final cursor = QuranPlaybackCursor(
      plan,
      introductionForSurah: _includeIntroduction,
    );
    cursor.introduction = cursor.needsIntroduction;
    await _install(_entry(cursor), generation, revision);
    if (_valid(generation, revision)) {
      _kickFill();
      if (_legacyPreparer == null) unawaited(downloadSelection(plan));
    }
  }

  void _cancelWork({bool cancelRecordings = true}) {
    _starting = false;
    _playRequest++;
    if (cancelRecordings) {
      _token.cancel('Playback selection replaced');
      _token = CancelToken();
    }
    _session++;
    _revision++;
    _fillRevision = null;
    _stall?.cancel();
    _installing = false;
    _download = const AudioDownloadState.idle();
  }

  Future<String> _prepare(_QueueEntry entry, {required bool urgent}) {
    if (entry.preparation != null &&
        urgent &&
        !entry.urgentPreparation &&
        entry.path == null &&
        _legacyPreparer == null) {
      entry.urgentPreparation = true;
      // Rejoin the repository job to promote it ahead of queued speculation.
      // The repository deduplicates physical recording identity within a session.
      unawaited(
        _repository
            .recording(_plan!.reciter, entry.item, _token, urgent: true)
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
    if (entry.preparation == null) entry.urgentPreparation = urgent;
    return entry.preparation ??= () async {
      if (_legacyPreparer != null) {
        final sources = await _legacyPreparer(_plan!);
        if (sources.isEmpty) throw StateError('No test recording supplied');
        final source = sources[entry.cursor.index.clamp(0, sources.length - 1)];
        if (source is! UriAudioSource) {
          throw StateError('Test fixture must be a URI source');
        }
        return source.uri.toString();
      }
      final generation = _session, revision = _revision;
      final reciter = _plan!.reciter;
      final path = await _repository.recording(
        reciter,
        entry.item,
        _token,
        urgent: urgent,
        onProgress: urgent
            ? (value) {
                if (!_valid(generation, revision) || entry != _waiting) return;
                _download = AudioDownloadState(
                  active: true,
                  completed: 0,
                  total: 1,
                  message: 'Downloading ${entry.item.label}',
                  fraction: value,
                );
                _publish();
              }
            : null,
      );
      if (generation == _session &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          reciter.id == 'abdullah_juhany') {
        entry.invertRightChannel = await _repository.needsStereoCorrection(
          path,
        );
      }
      return path;
    }();
  }

  AudioSource _source(_QueueEntry entry, String path) {
    final uri = _legacyPreparer == null ? Uri.file(path) : Uri.parse(path);
    return entry.source ??= entry.invertRightChannel
        ? ProgressiveAudioSource(
            uri,
            tag: entry.occurrence,
            options: const ProgressiveAudioSourceOptions(
              invertRightChannel: true,
            ),
          )
        : AudioSource.uri(uri, tag: entry.occurrence);
  }

  AudioFailure _problem(Object error) => error is AudioFailure
      ? error
      : const AudioFailure(
          AudioFailureKind.decoder,
          'The decoder could not play this recording.',
        );
  bool _alternative(_QueueEntry entry) {
    final primary = entry.primarySource;
    if (primary == null || entry.alternative >= primary.alternatives.length) {
      return false;
    }
    entry.alternative++;
    final old = entry.occurrence;
    entry.occurrence = QuranAudioOccurrence(
      occurrenceId: old.occurrenceId,
      item: QuranAudioItem(
        surah: old.item.surah,
        source: primary.alternatives[entry.alternative - 1],
      ),
      cursor: old.cursor,
      sessionGeneration: old.sessionGeneration,
    );
    entry.preparation = null;
    entry.path = null;
    entry.source = null;
    entry.failure = null;
    entry.attempts = 0;
    return true;
  }

  Future<void> _repair(_QueueEntry entry) async {
    if (_offlineToken != null && !_offlineToken!.isCancelled) {
      cancelDownload();
      _offlineNeedsRefresh = true;
    }
    await _repository.invalidate(_plan!.reciter, entry.item);
    _deferredFailures.remove(entry.item.recordingId);
    entry.preparation = null;
    entry.path = null;
    entry.source = null;
  }

  Future<bool> _readyEntry(
    _QueueEntry entry,
    int generation,
    int revision,
  ) async {
    while (_valid(generation, revision)) {
      try {
        if (entry.failure != null) {
          final failure = entry.failure!;
          if (_alternative(entry)) continue;
          if (!failure.recoverable || entry.attempts >= 4) {
            _fail(entry, failure);
            return false;
          }
          _phase = _intent
              ? QuranPlaybackPhase.recovering
              : QuranPlaybackPhase.paused;
          recoveryAttempt = entry.attempts.clamp(1, 3);
          _publish();
          await Future.any([
            Future<void>.delayed(retryDelay * (1 << (recoveryAttempt - 1))),
            _token.whenCancel.then<void>((_) {}),
          ]);
          if (!_valid(generation, revision)) return false;
          if (failure.kind == AudioFailureKind.decoder ||
              failure.kind == AudioFailureKind.corrupt) {
            await _repair(entry);
          }
          entry.failure = null;
        }
        entry.attempts++;
        entry.path = await _prepare(entry, urgent: true);
        return _valid(generation, revision);
      } catch (error) {
        if (!_valid(generation, revision)) return false;
        entry.preparation = null;
        entry.failure = _problem(error);
      }
    }
    return false;
  }

  Future<void> _install(
    _QueueEntry entry,
    int generation,
    int revision, {
    Duration position = Duration.zero,
  }) async {
    _installing = true;
    _starting = false;
    _playRequest++;
    _begun = false;
    _waiting = entry;
    _metadata(entry);
    if (entry.failure == null) {
      _phase = !_intent
          ? QuranPlaybackPhase.paused
          : _current == null
          ? QuranPlaybackPhase.preparing
          : QuranPlaybackPhase.buffering;
    }
    _publish();
    while (_valid(generation, revision)) {
      if (!await _readyEntry(entry, generation, revision)) {
        if (!_valid(generation, revision) || !entry.item.isIntroduction) break;
        entry = _omitIntroduction(entry);
        position = Duration.zero;
        _installing = true;
        _waiting = entry;
        _metadata(entry);
        _phase = _intent
            ? QuranPlaybackPhase.preparing
            : QuranPlaybackPhase.paused;
        continue;
      }
      try {
        await _native(() async {
          if (!_valid(generation, revision)) return;
          await _backend.pause().timeout(loadTimeout);
          if (!_valid(generation, revision)) return;
          _queue.clear();
          _queue.add(entry);
          _queueReloads++;
          await _backend
              .setAudioSources(
                [_source(entry, entry.path!)],
                initialIndex: 0,
                initialPosition: position,
              )
              .timeout(loadTimeout);
          if (!_valid(generation, revision)) return;
          await _backend.setLoopMode(LoopMode.off);
          if (_backend.processingState == ProcessingState.idle ||
              _backend.processingState == ProcessingState.completed) {
            throw StateError('Recording did not become ready');
          }
        });
        if (!_valid(generation, revision)) return;
        _installing = false;
        _download = const AudioDownloadState.idle();
        recoveryAttempt = 0;
        _adopt(entry, begun: false);
        _phase = _intent
            ? QuranPlaybackPhase.preparing
            : QuranPlaybackPhase.paused;
        if (_intent) _startNative(generation, revision);
        if (_offlineNeedsRefresh) {
          _offlineNeedsRefresh = false;
          unawaited(downloadSelection(_plan!));
        }
        _publish();
        return;
      } catch (error) {
        if (!_valid(generation, revision)) return;
        if (usingContinuousPcm) {
          await _fallbackContinuous(error);
          return;
        }
        await _backend.stop();
        if (!_valid(generation, revision)) return;
        entry.failure = _problem(error);
        entry.preparation = null;
        position = Duration.zero;
      }
    }
    if (_valid(generation, revision)) _installing = false;
  }

  _QueueEntry _omitIntroduction(_QueueEntry entry) {
    if (_offlineToken != null && !_offlineToken!.isCancelled) {
      cancelDownload();
      _offlineNeedsRefresh = true;
    }
    final source = entry.primarySource;
    if (source != null) _omittedIntroductions.add(source.id);
    introductionNotice =
        'Bismillah is unavailable for ${_plan!.reciter.name}. Continuing with the selected ayahs.';
    failure = null;
    _error = null;
    _failed = null;
    // Replan from ayah 1. A prefetched ayah 1 must not be appended twice.
    _pending.clear();
    final cursor = entry.cursor.copy()..advance(manual: true);
    return _entry(cursor);
  }

  void _startNative(int generation, int revision) {
    if (!_valid(generation, revision) ||
        !_intent ||
        _installing ||
        _starting ||
        _current == null) {
      return;
    }
    final request = ++_playRequest;
    _starting = true;
    _phase = _begun
        ? QuranPlaybackPhase.buffering
        : QuranPlaybackPhase.preparing;
    unawaited(
      _backend.play().then<void>(
        (_) {
          // A play Future normally ends at EOF/Pause. Some interrupted startup
          // paths return early in ready/false; recover those without another tap.
          if (_valid(generation, revision) &&
              request == _playRequest &&
              _intent &&
              !_installing &&
              !_exhausted &&
              _backend.processingState == ProcessingState.ready &&
              !_backend.playing) {
            unawaited(_recoverCurrent(invalidate: false));
          }
        },
        onError: (Object error) {
          if (_valid(generation, revision) &&
              request == _playRequest &&
              !_installing) {
            if (error is PlayerException) {
              _nativeError(error);
            } else {
              unawaited(_recoverCurrent(invalidate: false));
            }
          }
        },
      ),
    );
    // play() may update getters before its state stream delivers the event, or
    // may already be active. Awaiting its Future would wait until playback ends.
    _nativeState(PlayerState(_backend.playing, _backend.processingState));
  }

  void _fail(_QueueEntry entry, AudioFailure problem) {
    _failed = _waiting = entry;
    failure = problem;
    _error = '${entry.item.label}: ${problem.message}';
    _metadata(entry);
    _phase = QuranPlaybackPhase.failed;
    _installing = false;
    _starting = false;
    _playRequest++;
    _begun = false;
    _download = const AudioDownloadState.idle();
    _publish();
  }

  void _kickFill() {
    if (_pcmActive) return;
    if (!_active ||
        _installing ||
        phase == QuranPlaybackPhase.failed ||
        _current == null) {
      return;
    }
    final generation = _session, revision = _revision;
    if (_fillRevision == revision) {
      // An earlier download may still be pending while native playback moves
      // on. Keep the forward window prepared without reordering its append.
      _planPending();
      return;
    }
    _fillRevision = revision;
    unawaited(
      _fill(generation, revision).whenComplete(() {
        if (_fillRevision == revision) {
          _fillRevision = null;
          if (_valid(generation, revision) &&
              _exhausted &&
              phase != QuranPlaybackPhase.failed) {
            scheduleMicrotask(_kickFill);
          }
        }
      }),
    );
  }

  Future<void> _trim(int generation, int revision) async {
    await _native(() async {
      if (!_valid(generation, revision)) return;
      final index = _queue.indexOf(_current!);
      final remove = index - 1;
      if (remove <= 0) return;
      await _backend.removeAudioSourceRange(0, remove).timeout(loadTimeout);
      if (!_valid(generation, revision)) return;
      _queue.removeRange(0, remove);
    });
  }

  void _planPending() {
    final currentIndex = _queue.indexOf(_current!);
    final available = currentIndex < 0 ? 0 : _queue.length - currentIndex;
    var tail = _pending.lastOrNull ?? _queue.lastOrNull ?? _current!;
    while (available + _pending.length < forwardWindow + 1) {
      final next = _next(tail);
      if (next == null) break;
      _pending.add(next);
      tail = next;
      // Start I/O concurrently, but append strictly in logical occurrence order.
      next.attempts++;
      unawaited(
        _prepare(next, urgent: true).then<void>(
          (path) {
            next.path = path;
          },
          onError: (Object error) {
            next.preparation = null;
            next.failure = _problem(error);
          },
        ),
      );
    }
  }

  Future<void> _fill(int generation, int revision) async {
    try {
      while (_valid(generation, revision) && !_installing) {
        if (_exhausted) {
          final index = _queue.indexOf(_current!);
          if (index >= 0 && index + 1 < _queue.length) {
            final suffix = _queue.sublist(index + 1);
            _queue.removeRange(index + 1, _queue.length);
            _pending.removeWhere(suffix.contains);
            _pending.insertAll(0, suffix);
          }
        }
        await _trim(generation, revision);
        if (!_valid(generation, revision)) return;
        _planPending();
        if (_pending.isEmpty) {
          if (_next(_queue.lastOrNull ?? _current!) == null) {
            await _backend.finishQueue();
          }
          return;
        }
        final next = _pending.first;
        if (next.failure == null && next.path == null) {
          try {
            next.path = await _prepare(next, urgent: _exhausted);
          } catch (error) {
            next.preparation = null;
            next.failure = _problem(error);
          }
        }
        if (!_valid(generation, revision)) return;
        if (next.failure != null && !_exhausted) return;
        if (_exhausted) {
          _pending.removeAt(0);
          _waiting = next;
          _metadata(next);
          await _install(next, generation, revision);
          if (!_valid(generation, revision) ||
              phase == QuranPlaybackPhase.failed) {
            return;
          }
          // A genuinely exhausted queue was rebuilt; previously planned pending
          // entries remain the exact following occurrences, without replaying intro.
          continue;
        }
        if (next.failure != null) return;
        await _native(() async {
          if (!_valid(generation, revision)) return;
          if (_queue.length >= nativeQueueLimit) return;
          _queue.add(next);
          try {
            await _backend
                .addAudioSource(_source(next, next.path!))
                .timeout(loadTimeout);
          } catch (error) {
            next.failure = _problem(error);
            rethrow;
          }
          if (_valid(generation, revision)) _pending.remove(next);
        });
        if (_exhausted) continue;
        if (_pending.isEmpty && _next(next) == null) {
          await _backend.finishQueue();
        }
        if (_queue.length >= nativeQueueLimit) return;
        final index = _queue.indexOf(_current!);
        if (index >= 0 && _queue.length - index >= forwardWindow + 1) return;
      }
    } catch (error) {
      if (!_valid(generation, revision)) return;
      if (usingContinuousPcm) {
        await _fallbackContinuous(error);
        return;
      }
      // An append failure belongs to the appended future recording, not current.
      final broken = _queue.where((e) => e.failure != null).firstOrNull;
      if (broken != null) {
        await _deferFutureFailure(broken, generation, revision);
      } else if (_exhausted && _pending.isNotEmpty) {
        _fail(_pending.first, _problem(error));
      }
    }
  }

  Future<void> _endOfQueue() async {
    if (_pcmActive) {
      _active = _intent = _begun = false;
      _phase = QuranPlaybackPhase.completed;
      _tracker?.flush();
      await _backend.pause();
      _publish();
      return;
    }
    if (!_active || _current == null) return;
    // A native automatic transition may have overtaken the EOF callback.
    if (_backend.processingState != ProcessingState.completed) {
      _exhausted = false;
      return;
    }
    final currentIndex = _queue.indexOf(_current!);
    if ((currentIndex < 0 || currentIndex + 1 >= _queue.length) &&
        _pending.isEmpty &&
        _next(_current!) == null) {
      _active = false;
      _intent = false;
      _phase = QuranPlaybackPhase.completed;
      _tracker?.flush();
      await _backend.pause();
      _publish();
      return;
    }
    _phase = _intent ? QuranPlaybackPhase.buffering : QuranPlaybackPhase.paused;
    if (_pending.isNotEmpty) {
      unawaited(
        _prepare(
          _pending.first,
          urgent: true,
        ).then<void>((_) {}, onError: (Object _) {}),
      );
    }
    _publish();
    _kickFill();
  }

  void _nativeError(PlayerException error) {
    if (_active && usingContinuousPcm) {
      unawaited(_fallbackContinuous(error));
      return;
    }
    if (!_active || _installing || phase == QuranPlaybackPhase.failed) return;
    final index = error.index;
    final nativeSequence = _backend.sequenceState.sequence;
    final sourceTag =
        index != null && index >= 0 && index < nativeSequence.length
        ? nativeSequence[index].tag
        : null;
    final affected =
        sourceTag is QuranAudioOccurrence &&
            sourceTag.sessionGeneration == _session
        ? _queue
              .where(
                (entry) =>
                    entry.occurrence.occurrenceId == sourceTag.occurrenceId,
              )
              .firstOrNull
        : null;
    if (affected != null && affected != _current) {
      affected.failure = const AudioFailure(
        AudioFailureKind.decoder,
        'A prepared recording failed to decode.',
      );
      if (_deferredFailures.length >= nativeQueueLimit) {
        _deferredFailures.remove(_deferredFailures.keys.first);
      }
      _deferredFailures[affected.item.recordingId] = affected.failure!;
      final generation = _session, revision = _revision;
      unawaited(() async {
        await _deferFutureFailure(affected, generation, revision);
        if (_valid(generation, revision) &&
            _backend.processingState == ProcessingState.idle) {
          await _recoverCurrent(invalidate: false);
        }
      }());
      return;
    }
    unawaited(_recoverCurrent(invalidate: affected == _current));
  }

  Future<void> _deferFutureFailure(
    _QueueEntry entry,
    int generation,
    int revision,
  ) async {
    await _native(() async {
      if (!_valid(generation, revision)) return;
      final index = _queue.indexOf(entry), current = _queue.indexOf(_current!);
      if (index <= current || index < 0) return;
      final suffix = _queue.sublist(index);
      await _backend
          .removeAudioSourceRange(index, _queue.length)
          .timeout(loadTimeout);
      if (!_valid(generation, revision)) return;
      _queue.removeRange(index, _queue.length);
      _pending.removeWhere((e) => suffix.contains(e));
      _pending.insertAll(0, suffix);
    });
    if (_valid(generation, revision) && _exhausted) _kickFill();
  }

  Future<void> _recoverCurrent({required bool invalidate}) async {
    if (usingContinuousPcm) {
      await _fallbackContinuous(StateError('Continuous output stalled'));
      return;
    }
    if (_pcmActive) {
      await _fallbackPcmProof(_session, _revision);
      return;
    }
    final entry = _current;
    if (!_active || _installing || entry == null) return;
    if (entry.decoderRestarts++ >= 3) {
      if (entry.item.isIntroduction) {
        final generation = _session, revision = ++_revision;
        _fillRevision = null;
        await _install(_omitIntroduction(entry), generation, revision);
        if (_valid(generation, revision)) _kickFill();
        return;
      }
      _fail(
        entry,
        const AudioFailure(
          AudioFailureKind.decoder,
          'Repeated decoder failures. Retry, skip, or stop.',
        ),
      );
      await _backend.pause();
      return;
    }
    var position = _backend.position;
    _token.cancel('Recovering native queue');
    _token = CancelToken();
    final generation = _session, revision = ++_revision;
    _installing = true;
    _fillRevision = null;
    _pending.clear();
    _phase = _intent
        ? QuranPlaybackPhase.recovering
        : QuranPlaybackPhase.paused;
    _publish();
    await _backend.pause();
    if (!_valid(generation, revision)) return;
    if (invalidate) {
      await _repair(entry);
      if (!_valid(generation, revision)) return;
      if (entry.item.isIntroduction && _alternative(entry)) {
        position = Duration.zero;
      }
    }
    entry.failure = null;
    entry.attempts = 0;
    await _install(entry, generation, revision, position: position);
    if (_valid(generation, revision)) _kickFill();
  }

  Future<void> _fallbackContinuous(Object reason) async {
    if (!usingContinuousPcm || !_active || _continuousHandoff) return;
    final failedBackend = _backend;
    final pcm = failedBackend is ContinuousPcmBackend ? failedBackend : null;
    // Only the rendered cursor is authoritative. A failure in a future decode
    // must never skip from the audible ayah to the failed future recording.
    final entry = _installing ? _waiting : _current ?? _waiting;
    final position = _installing || entry == null || entry != _current
        ? null
        : pcm?.recoveryPosition(entry.occurrence.occurrenceId, entry.source);
    final generation = _session, revision = ++_revision;
    _token.cancel('Continuous backend handoff');
    _token = CancelToken();
    _fillRevision = null;
    _installing = true;
    _starting = false;
    _playRequest++;
    _stall?.cancel();
    final retryNative = position != null && !entry!.retriedRenderedPosition;
    if (!kReleaseMode) {
      debugPrint(
        'Quran PCM recovery reciter=${_plan!.reciter.id} recording=${entry?.item.recordingId} '
        'occurrence=${entry?.occurrence.occurrenceId} repeat=${entry?.cursor.repetition} '
        'generation=$generation revision=$revision position=$position nativeRetry=$retryNative '
        'reason=$reason ${pcm?.diagnostics}',
      );
    }
    if (retryNative) {
      entry.retriedRenderedPosition = true;
      _pending.clear();
      // _install reuses this occurrence's prepared source and the same decoder.
      // prepare cancels its old output before installing the new generation.
      await _install(entry, generation, revision, position: position);
      if (_valid(generation, revision)) _kickFill();
      return;
    }
    _continuousHandoff = true;
    _retiringBackend = failedBackend;
    continuousFallbackReason =
        '$reason (legacy seek equivalence unverified; restart current occurrence)';
    try {
      // Release output before the legacy player can activate the shared session.
      await failedBackend.dispose();
      if (!_valid(generation, revision)) return;
      _bindBackend(_legacyBackend);
      _queue.clear();
      _pending.clear();
      _tracker?.flush();
      _current = _waiting = _failed = null;
      _begun = _exhausted = false;
      if (entry == null) return;
      entry.source = null;
      entry.failure = null;
      entry.attempts = 0;
      await _install(entry, generation, revision);
      if (_valid(generation, revision)) {
        _kickFill();
        if (_legacyPreparer == null) unawaited(downloadSelection(_plan!));
      }
    } catch (error) {
      if (_valid(generation, revision) && entry != null) {
        _fail(entry, _problem(error));
      }
    } finally {
      _continuousHandoff = false;
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
    if (_installing || _current == null) {
      _phase = _current == null
          ? QuranPlaybackPhase.preparing
          : QuranPlaybackPhase.buffering;
    } else if (_exhausted) {
      _phase = QuranPlaybackPhase.buffering;
    } else {
      _startNative(_session, _revision);
    }
    _publish();
  }

  Future<void> pause() async {
    if (!_active) return;
    _intent = false;
    _starting = false;
    _playRequest++;
    _stall?.cancel();
    if (phase != QuranPlaybackPhase.failed) {
      _phase = QuranPlaybackPhase.paused;
    }
    _trackListening();
    _publish();
    await _backend.pause();
  }

  Future<void> togglePlayPause() => playing ? pause() : play();
  Future<void> retry() async {
    final entry = _failed;
    if (!_active || entry == null) return;
    entry.attempts = 0;
    entry.decoderRestarts = 0;
    if (entry.failure?.kind == AudioFailureKind.decoder ||
        entry.failure?.kind == AudioFailureKind.corrupt) {
      await _repair(entry);
    }
    entry.failure = null;
    entry.preparation = null;
    failure = null;
    _error = null;
    final generation = _session, revision = ++_revision;
    _fillRevision = null;
    await _install(entry, generation, revision);
    if (_valid(generation, revision)) _kickFill();
  }

  void clearError() {
    if (phase == QuranPlaybackPhase.failed) return;
    failure = null;
    _error = null;
    _publish();
  }

  Future<void> stop() async {
    _pcmActive = false;
    _pcmRow = null;
    _active = false;
    _intent = false;
    _begun = false;
    cancelDownload();
    _cancelWork();
    _tracker?.reset();
    _queue.clear();
    _pending.clear();
    _current = _failed = _waiting = null;
    failure = null;
    _error = null;
    _media = null;
    _phase = QuranPlaybackPhase.idle;
    _publish();
    await _backend.stop();
  }

  Future<void> _navigate(bool next) async {
    if (_pcmActive) {
      await _navigatePcm(next);
      return;
    }
    if (!_active || _display == null) return;
    final old = _display!;
    final cursor = old.cursor.copy();
    if (next && old.item.isIntroduction) {
      final source = old.primarySource;
      if (_failed != null && source != null) {
        _omittedIntroductions.add(source.id);
      }
    }
    if (next) {
      if (!cursor.advance(manual: true)) {
        await stop();
        return;
      }
    } else {
      cursor.previous();
    }
    // Navigation changes occurrences, not the selected offline recordings.
    // Keep bounded in-flight acquisitions so the new window can rejoin them
    // instead of aborting and downloading an already-received file again.
    _cancelWork(cancelRecordings: false);
    final generation = _session, revision = _revision;
    _queue.clear();
    _pending.clear();
    _current = _failed = _waiting = null;
    _begun = false;
    await _backend.stop();
    if (!_valid(generation, revision)) return;
    await _install(_entry(cursor), generation, revision);
    if (_valid(generation, revision)) _kickFill();
  }

  Future<void> seekNext() => _navigate(true);
  Future<void> seekPrevious() => _navigate(false);
  Future<void> seek(Duration position) async {
    if (_pcmActive) {
      if (_installing || !_active) return;
      final start = _pcmProof!.time(_pcmRow!.startFrame);
      final duration = _pcmProof!.time(_pcmRow!.endFrame) - start;
      await _seekPcm(
        start +
            Duration(
              microseconds: position.inMicroseconds.clamp(
                0,
                duration.inMicroseconds,
              ),
            ),
      );
      return;
    }
    if (!_active || _installing || _exhausted || _current == null) return;
    try {
      await _backend.seek(position);
    } catch (error) {
      if (!usingContinuousPcm) rethrow;
      await _fallbackContinuous(error);
    }
    _trackListening();
    _publish();
  }

  Future<void> downloadSelection(AudioPlaybackPlan selection) async {
    if (_pcmActive && selection.matches(_plan)) return;
    _offlineToken?.cancel('New offline selection');
    final token = _offlineToken = CancelToken();
    final items = <String, QuranAudioItem>{};
    var unavailable = 0;
    for (final verse in selection.uniqueVerses()) {
      if (verse.ayah == 1) {
        final resolution = resolveIntroduction(selection.reciter, verse.surah);
        if (resolution.kind == BismillahPolicyKind.unverified) unavailable++;
        if (resolution.kind == BismillahPolicyKind.separateVerifiedRecording &&
            resolution.source != null) {
          items[resolution.source!.id] = QuranAudioItem(
            surah: verse.surah,
            source: resolution.source,
          );
        }
      }
      final item = _resolvedItem(
        selection.reciter,
        QuranAudioItem(surah: verse.surah, ayah: verse.ayah),
      );
      // A canonical 001001 can also be the numbered Fatihah 1:1 recording.
      items.putIfAbsent(item.recordingId, () => item);
    }
    var done = 0;
    var failed = 0;
    try {
      for (final item in items.values) {
        if (token.isCancelled) throw token.cancelError!;
        if (item.isIntroduction &&
            _omittedIntroductions.contains(item.recordingId)) {
          failed++;
          continue;
        }
        _offlineDownload = AudioDownloadState(
          active: true,
          completed: done,
          total: items.length,
          message: 'Saving audio offline · $done/${items.length}',
        );
        _publish();
        var saved = false;
        for (var attempt = 0; attempt < 4; attempt++) {
          try {
            await _repository.recording(
              selection.reciter,
              item,
              token,
              urgent: false,
            );
            saved = true;
            break;
          } catch (error) {
            if (token.isCancelled) throw token.cancelError!;
            final problem = _problem(error);
            if (!problem.recoverable || attempt == 3) break;
            await Future.any([
              Future<void>.delayed(retryDelay * (1 << attempt)),
              token.whenCancel.then<void>((_) {}),
            ]);
            if (token.isCancelled) throw token.cancelError!;
          }
        }
        if (saved) {
          done++;
        } else {
          failed++;
        }
      }
      if (!token.isCancelled && _offlineToken == token) {
        _offlineDownload = AudioDownloadState(
          active: false,
          completed: done,
          total: items.length,
          message: unavailable == 0 && failed == 0
              ? 'Selection available offline'
              : 'Offline audio incomplete · $failed recording(s) unavailable'
                    '${unavailable == 0 ? "" : "; Bismillah unavailable for $unavailable opening(s)"}',
        );
      }
    } catch (error) {
      if (!token.isCancelled && _offlineToken == token) {
        _offlineDownload = AudioDownloadState(
          active: false,
          completed: done,
          total: items.length,
          message: 'Offline saving stopped: $error',
        );
      }
    }
    _publish();
  }

  void cancelDownload() {
    _offlineToken?.cancel();
    _offlineToken = null;
    _offlineNeedsRefresh = false;
    _offlineDownload = const AudioDownloadState.idle();
    _publish();
  }

  Future<void> prepareArtwork() async {
    try {
      _artwork = await prepareAudioArtwork(
        await getApplicationSupportDirectory(),
      );
    } catch (_) {}
  }

  static String audioId(int surah, int ayah) =>
      AudioRepository.audioId(surah, ayah);
  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _token.cancel();
    _offlineToken?.cancel();
    _stall?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _tracker?.reset();
    unawaited(_backend.dispose());
    if (usingContinuousPcm) unawaited(_legacyBackend.dispose());
    super.dispose();
  }
}
