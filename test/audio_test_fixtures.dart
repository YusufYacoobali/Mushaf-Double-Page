import 'dart:async';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';

/// Only synthetic test policy. This is never evidence about EveryAyah content.
BismillahResolution fixtureIntroduction(Reciter reciter, int surah) =>
    surah == 1 || surah == 9
    ? const BismillahResolution(
        BismillahPolicyKind.notRequired,
        evidence: 'Product rule',
      )
    : BismillahResolution(
        BismillahPolicyKind.separateVerifiedRecording,
        source: AudioRecordingSource(
          id: '${reciter.id}/intro-$surah',
          url: 'https://example.test/$surah/intro.mp3',
          cacheFilename: '${surah}000.mp3',
          verification: 'Synthetic fixture, not a real recording',
        ),
        evidence: 'Synthetic fixture',
      );

class FakePlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final sequences = StreamController<SequenceState>.broadcast(sync: true);
  final queue = <AudioSource>[];
  final loadedSources = <AudioSource>[];
  final loadedPositions = <Duration?>[];
  final played = <QuranAudioOccurrence>[];
  int starts = 0,
      sourceLoads = 0,
      pauses = 0,
      stops = 0,
      appends = 0,
      appendAttempts = 0,
      removals = 0,
      seeks = 0;
  int generation = 0, failLoads = 0, failPlays = 0, maxQueue = 0;
  bool active = false;
  ProcessingState state = ProcessingState.idle;
  Completer<void>? loadGate, appendGate;
  Duration at = Duration.zero;
  Duration? durationOverride;
  int index = 0;
  @override
  LoopMode loopMode = LoopMode.off;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<SequenceState> get sequenceStateStream => sequences.stream;
  @override
  SequenceState get sequenceState => SequenceState(
    sequence: List<IndexedAudioSource>.of(queue.cast<IndexedAudioSource>()),
    currentIndex: queue.isEmpty ? null : index,
    shuffleIndices: List.generate(queue.length, (i) => i),
    shuffleModeEnabled: false,
    loopMode: loopMode,
  );
  @override
  List<IndexedAudioSource> get sequence => queue.cast<IndexedAudioSource>();
  @override
  int? get currentIndex => queue.isEmpty ? null : index;
  @override
  int get retainedAudioSourceCount => queue.length + 1;
  @override
  Duration get position => at;
  @override
  Duration get bufferedPosition => at;
  @override
  Duration? get duration => durationOverride ?? const Duration(seconds: 10);
  @override
  bool get playing => active;
  @override
  ProcessingState get processingState => state;
  void _emitSequence() {
    sequences.add(sequenceState);
  }

  void _record() {
    final tag = sequenceState.currentSource?.tag;
    if (tag is QuranAudioOccurrence &&
        (played.isEmpty || played.last.occurrenceId != tag.occurrenceId)) {
      played.add(tag);
    }
  }

  @override
  Future<void> play() async {
    if (active) return;
    starts++;
    active = true;
    if (failPlays-- > 0) {
      errors.add(PlayerException(1, 'decoder', index));
      return;
    }
    _record();
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> stop() async {
    generation++;
    stops++;
    active = false;
    state = ProcessingState.idle;
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> pause() async {
    pauses++;
    active = false;
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks++;
    at = position ?? Duration.zero;
    if (index != null) {
      this.index = index;
      _emitSequence();
    }
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    final load = ++generation;
    sourceLoads++;
    loadedSources.addAll(sources);
    loadedPositions.add(initialPosition);
    await loadGate?.future;
    if (load != generation) throw StateError('Loading interrupted');
    if (failLoads-- > 0) throw PlayerException(1, 'decoder', 0);
    queue
      ..clear()
      ..addAll(sources);
    index = initialIndex ?? 0;
    at = initialPosition ?? Duration.zero;
    if (queue.length > maxQueue) maxQueue = queue.length;
    state = ProcessingState.ready;
    _emitSequence();
    states.add(PlayerState(active, state));
    return duration;
  }

  @override
  Future<void> addAudioSource(AudioSource source) async {
    appendAttempts++;
    final load = generation;
    await appendGate?.future;
    if (load != generation) throw StateError('Append interrupted');
    appends++;
    queue.add(source);
    if (queue.length > maxQueue) maxQueue = queue.length;
    _emitSequence();
  }

  @override
  Future<void> removeAudioSourceRange(int start, int end) async {
    removals++;
    queue.removeRange(start, end);
    if (index >= end) {
      index -= end - start;
    } else if (index >= start) {
      index = start;
    }
    _emitSequence();
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopMode = mode;
  }

  /// Native automatic transition: no controller seek/reload is involved.
  void advance() {
    if (index + 1 < queue.length) {
      index++;
      at = Duration.zero;
      state = ProcessingState.ready;
      _record();
      _emitSequence();
      states.add(PlayerState(active, state));
    } else {
      complete();
    }
  }

  void complete() {
    state = ProcessingState.completed;
    states.add(PlayerState(active, state));
  }

  void buffering() {
    active = false;
    state = ProcessingState.buffering;
    states.add(PlayerState(active, state));
  }

  void fail({int? sourceIndex}) =>
      errors.add(PlayerException(1, 'source failed', sourceIndex ?? index));
  @override
  Future<void> dispose() async {
    await states.close();
    await errors.close();
    await positions.close();
    await sequences.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ControlledRepository implements AudioRecordingRepository {
  final invertedFiles = <String>{};
  final stereoChecks = <String>[];
  @override
  Future<bool> needsStereoCorrection(String path) async {
    stereoChecks.add(path);
    return invertedFiles.contains(path);
  }

  final sourceIds = <String>[];
  final _inFlight = <String, Future<String>>{};
  final requested = <String>[],
      urgentRequests = <String>[],
      invalidated = <String>[];
  final remainingFailures = <String, int>{};
  final failures = <String, AudioFailure>{};
  final gates = <String, Completer<void>>{};
  final cancelled = <CancelToken>[];
  bool failPrefetch = false;
  @override
  Future<String> recording(
    Reciter reciter,
    QuranAudioItem item,
    CancelToken token, {
    bool urgent = true,
    void Function(double)? onProgress,
  }) async {
    final key = '${reciter.id}/${item.key}';
    if (urgent) urgentRequests.add(key);
    final jobKey = '${identityHashCode(token)}:$key';
    if (_inFlight.containsKey(jobKey)) return _inFlight[jobKey]!;
    sourceIds.add(item.recordingId);
    requested.add(key);
    cancelled.add(token);
    final request = () async {
      await gates[item.key]?.future;
      if (token.isCancelled) throw token.cancelError!;
      if (!urgent && failPrefetch) {
        throw const AudioFailure(
          AudioFailureKind.connectivity,
          'Offline prefetch',
        );
      }
      final count = remainingFailures[item.key] ?? 0;
      if (count > 0) {
        remainingFailures[item.key] = count - 1;
        throw failures[item.key] ??
            const AudioFailure(AudioFailureKind.connectivity, 'Offline');
      }
      onProgress?.call(1);
      return '/audio/$key.mp3';
    }();
    _inFlight[jobKey] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(jobKey);
    }
  }

  @override
  Future<void> invalidate(Reciter reciter, QuranAudioItem item) async {
    invalidated.add(item.key);
  }
}

AudioPlaybackPlan plan({
  int surah = 112,
  int from = 2,
  int to = 4,
  int? count = 1,
  AudioRepeatMode repeat = AudioRepeatMode.range,
  List<int> queue = const [],
  Reciter? reciter,
}) => AudioPlaybackPlan(
  reciter: reciter ?? quranReciters.first,
  surah: surah,
  fromAyah: from,
  toAyah: to,
  repeatCount: count,
  repeatMode: repeat,
  sourceMode: queue.isEmpty ? AudioSourceMode.range : AudioSourceMode.playlist,
  surahQueue: queue,
);
Future<void> flush() async {
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
