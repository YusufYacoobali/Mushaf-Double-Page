import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/quran_audio.dart';

/// The controller owns planning and intent; a backend only renders its bounded
/// recording queue. just_audio value types also keep the Stage-A probe usable.
abstract interface class AudioPlaybackBackend {
  Stream<Duration> get positionStream;
  Stream<SequenceState> get sequenceStateStream;
  Stream<PlayerState> get playerStateStream;
  Stream<PlayerException> get errorStream;
  SequenceState get sequenceState;
  Duration get position;
  Duration get bufferedPosition;
  Duration? get duration;
  bool get playing;
  ProcessingState get processingState;
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    int? initialIndex,
    Duration? initialPosition,
  });
  Future<void> addAudioSource(AudioSource source);
  Future<void> removeAudioSourceRange(int start, int end);
  Future<void> finishQueue();
  Future<void> setLoopMode(LoopMode mode);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

class JustAudioBackend implements AudioPlaybackBackend {
  JustAudioBackend(this.player);
  final AudioPlayer player;
  @override
  Stream<Duration> get positionStream => player.positionStream;
  @override
  Stream<SequenceState> get sequenceStateStream => player.sequenceStateStream;
  @override
  Stream<PlayerState> get playerStateStream => player.playerStateStream;
  @override
  Stream<PlayerException> get errorStream => player.errorStream;
  @override
  SequenceState get sequenceState => player.sequenceState;
  @override
  Duration get position => player.position;
  @override
  Duration get bufferedPosition => player.bufferedPosition;
  @override
  Duration? get duration => player.duration;
  @override
  bool get playing => player.playing;
  @override
  ProcessingState get processingState => player.processingState;
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    int? initialIndex,
    Duration? initialPosition,
  }) => player.setAudioSources(
    sources,
    initialIndex: initialIndex,
    initialPosition: initialPosition,
  );
  @override
  Future<void> addAudioSource(AudioSource source) =>
      player.addAudioSource(source);
  @override
  Future<void> removeAudioSourceRange(int start, int end) =>
      player.removeAudioSourceRange(start, end);
  @override
  Future<void> finishQueue() async {}
  @override
  Future<void> setLoopMode(LoopMode mode) => player.setLoopMode(mode);
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> dispose() => player.dispose();
}

/// A bounded, decoded timeline row. End is unknown until the decoder reaches
/// EOF; decoded is the exact frame count available so far, never a duration hint.
class PcmTimelineRow {
  PcmTimelineRow(Map<Object?, Object?> value)
    : id = value['id']! as String,
      start = (value['start']! as num).toInt(),
      end = (value['end'] as num?)?.toInt(),
      decoded = (value['decoded']! as num).toInt();
  final String id;
  final int start, decoded;
  final int? end;
}

/// Native decoders and PCM never cross the Flutter channel. Only file identities,
/// commands and a 10 Hz rendered-frame clock do. No audio session is created here:
/// activation uses the same audio_session configuration as QuranAudioHandler.
class ContinuousPcmBackend implements AudioPlaybackBackend {
  ContinuousPcmBackend({
    MethodChannel? channel,
    Stream<dynamic>? events,
    Future<bool> Function(bool)? activateSession,
    this.bufferSeconds = 8,
  }) : _channel = channel ?? const MethodChannel('quran/pcm'),
       _activateSession = activateSession ?? _activate {
    if (bufferSeconds < 1 || bufferSeconds > 15) {
      throw ArgumentError.value(bufferSeconds, 'bufferSeconds');
    }
    _subscription =
        (events ??
                const EventChannel('quran/pcm/events').receiveBroadcastStream())
            .listen(_event, onError: _error);
  }
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static const sampleRate = 44100;
  static int _nextGeneration = 0;
  static Future<bool> _activate(bool active) async =>
      (await AudioSession.instance).setActive(active);
  final MethodChannel _channel;
  final Future<bool> Function(bool) _activateSession;
  final int bufferSeconds;
  late final StreamSubscription<dynamic> _subscription;
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _sequences = StreamController<SequenceState>.broadcast(sync: true);
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final _errors = StreamController<PlayerException>.broadcast(sync: true);
  final _sources = <IndexedAudioSource>[];
  List<PcmTimelineRow> _rows = [];
  int _generation = 0, _command = 0, _index = 0, _frames = 0, _buffered = 0;
  bool _playing = false, _disposed = false, _failed = false;
  bool _queueFinished = false;
  Future<void>? _disposal;
  ProcessingState _state = ProcessingState.idle;
  int underruns = 0;
  Map<String, Object?> diagnostics = const {};
  List<PcmTimelineRow> get timeline => List.unmodifiable(_rows);
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<SequenceState> get sequenceStateStream => _sequences.stream;
  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  Stream<PlayerException> get errorStream => _errors.stream;
  String _id(IndexedAudioSource source) =>
      (source.tag as QuranAudioOccurrence).occurrenceId;
  PcmTimelineRow? get _row => _sources.isEmpty
      ? null
      : _rows.where((r) => r.id == _id(_sources[_index])).firstOrNull;
  Duration _time(int frames) => Duration(
    microseconds: frames * Duration.microsecondsPerSecond ~/ sampleRate,
  );

  /// Safe only when restarting this native decoder on the same prepared file.
  /// Round the microseconds UP so prepare's floor conversion is frame-exact.
  Duration? recoveryPosition(String occurrence, AudioSource? source) {
    final row = _row;
    if (row == null ||
        row.id != occurrence ||
        !identical(_sources[_index], source)) {
      return null;
    }
    final offset = _frames - row.start;
    if (offset <= 0 ||
        offset > row.decoded ||
        (row.end != null && _frames >= row.end!)) {
      return null;
    }
    return Duration(
      microseconds:
          (offset * Duration.microsecondsPerSecond + sampleRate - 1) ~/
          sampleRate,
    );
  }

  /// Sample the output worker even when UI-thread telemetry has been delayed.
  Future<void> refreshClock() async {
    final snapshot = await _channel.invokeMethod<dynamic>('snapshot', {
      'generation': _generation,
    });
    // A pushed event may have passed the sampled position while the method
    // reply was in flight. A seek or reinstall uses a new generation.
    if (snapshot is Map &&
        (snapshot['frames'] as num?) != null &&
        (snapshot['frames'] as num) >= _frames) {
      _event(snapshot);
    }
  }

  @override
  Duration get position =>
      _time((_frames - (_row?.start ?? 0)).clamp(0, _row?.decoded ?? _frames));
  @override
  Duration get bufferedPosition => _time(
    (_buffered - (_row?.start ?? 0)).clamp(0, _row?.decoded ?? _buffered),
  );
  @override
  Duration? get duration =>
      _row?.end == null ? null : _time(_row!.end! - _row!.start);
  @override
  bool get playing => _playing;
  @override
  ProcessingState get processingState => _state;
  @override
  SequenceState get sequenceState => SequenceState(
    sequence: List.of(_sources),
    currentIndex: _sources.isEmpty ? null : _index,
    shuffleIndices: List.generate(_sources.length, (i) => i),
    shuffleModeEnabled: false,
    loopMode: LoopMode.off,
  );
  Map<String, Object> _recording(IndexedAudioSource source) => {
    'id': _id(source),
    'path': (source as UriAudioSource).uri.toFilePath(),
    if (source is ProgressiveAudioSource && source.options != null)
      'polarity': source.options!.invertRightChannel ? 'inverted' : 'normal',
  };
  Future<void> _invoke(String method, [Map<String, Object>? args]) async {
    await _channel.invokeMethod<void>(method, {
      'generation': _generation,
      ...?args,
    });
  }

  void _emitState() {
    if (!_disposed) _states.add(PlayerState(_playing, _state));
  }

  void _error(Object error) {
    if (_disposed || _failed) return;
    _failed = true;
    _errors.add(PlayerException(-100, 'Continuous PCM: $error', _index));
  }

  void _event(dynamic raw) {
    if (_disposed || _failed || raw is! Map) return;
    if (raw['generation'] != _generation) return;
    final problem = raw['error'];
    if (problem != null && (raw['rows'] == null || raw['frames'] == null)) {
      _error(problem as Object);
      return;
    }
    _rows = (raw['rows'] as List)
        .map((r) => PcmTimelineRow(Map<Object?, Object?>.from(r as Map)))
        .toList();
    _frames = (raw['frames'] as num).toInt();
    _buffered = (raw['bufferedFrames'] as num).toInt();
    final previousUnderruns = underruns;
    underruns = (raw['underruns'] as num?)?.toInt() ?? 0;
    diagnostics = {
      'underruns': underruns,
      'pcmBufferedFrames': raw['pcmBufferedFrames'],
      'pcmCapacityFrames': raw['pcmCapacityFrames'],
      'renderedFrames': _frames,
      'scheduledFrames': raw['scheduledFrames'] ?? _buffered,
      'decodedFrames': raw['decodedFrames'] ?? _buffered,
      'scheduledBuffers': raw['scheduledBuffers'],
      'completedBuffers': raw['completedBuffers'],
      'scheduleWaitMaxMs': raw['scheduleWaitMaxMs'],
      'queuedRecordings': raw['queuedRecordings'],
      'decodingOccurrence': raw['decodingOccurrence'],
      'minBufferedFrames': raw['minBufferedFrames'],
    };
    if (underruns > previousUnderruns) {
      debugPrint('Quran PCM underrun: $diagnostics');
    }
    final row = _rows
        .where((r) => _frames >= r.start && (r.end == null || _frames < r.end!))
        .firstOrNull;
    final index = row == null
        ? -1
        : _sources.indexWhere((s) => _id(s) == row.id);
    _state = switch (raw['state']) {
      'ready' => ProcessingState.ready,
      'completed' => ProcessingState.completed,
      'buffering' => ProcessingState.buffering,
      _ => ProcessingState.loading,
    };
    // Native acknowledgements never change the controller's Play/Pause intent.
    // A paused command is synchronous here, so stale telemetry cannot undo it.
    if (index >= 0 && index != _index) {
      _index = index;
      _sequences.add(sequenceState);
    }
    _positions.add(position);
    // Adopt the rendered occurrence from the error's snapshot before handing
    // off. A delayed UI event must not replay an already-finished prior ayah.
    if (problem != null) {
      _error(problem as Object);
      return;
    }
    _emitState();
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    if (_disposal != null) throw StateError('PCM backend has been released');
    _command++;
    _generation = ++_nextGeneration;
    _failed = false;
    _queueFinished = false;
    _playing = false;
    _state = ProcessingState.loading;
    _sources
      ..clear()
      ..addAll(sources.cast<IndexedAudioSource>());
    _index = initialIndex ?? 0;
    _rows = [];
    _frames = _buffered = 0;
    final generation = _generation;
    await _invoke('prepare', {
      'sources': _sources.skip(_index).map(_recording).toList(),
      'seekFrames':
          (initialPosition ?? Duration.zero).inMicroseconds *
          sampleRate ~/
          Duration.microsecondsPerSecond,
      'bufferSeconds': bufferSeconds,
    });
    if (_disposed || generation != _generation) return null;
    _sequences.add(sequenceState);
    _emitState();
    return duration;
  }

  @override
  Future<void> addAudioSource(AudioSource source) async {
    final indexed = source as IndexedAudioSource;
    _sources.add(indexed);
    await _invoke('enqueue', _recording(indexed));
  }

  @override
  Future<void> removeAudioSourceRange(int start, int end) async {
    final removed = _sources.sublist(start, end).map(_id).toList();
    await _invoke('remove', {'ids': removed});
    _sources.removeRange(start, end);
    _index = (_index - (end - start)).clamp(0, _sources.length - 1);
  }

  @override
  Future<void> finishQueue() {
    _queueFinished = true;
    return _invoke('finish');
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    if (mode != LoopMode.off) throw UnsupportedError('Controller owns repeats');
  }

  @override
  Future<void> play() async {
    final command = ++_command;
    if (!await _activateSession(true)) throw StateError('Audio focus denied');
    if (_disposed || _disposal != null || command != _command) return;
    _playing = true;
    await _invoke('play');
    _emitState();
  }

  @override
  Future<void> pause() async {
    _command++;
    _playing = false;
    _emitState();
    await _invoke('pause');
  }

  @override
  Future<void> stop() async {
    _command++;
    _generation = ++_nextGeneration;
    _playing = false;
    _state = ProcessingState.idle;
    _emitState();
    try {
      await _invoke('stop');
    } on MissingPluginException {
      // No native plugin also means no native output exists to stop. This is
      // the supported handoff path on platforms without the PCM implementation.
    }
    await _activateSession(false);
    _sources.clear();
    _rows = [];
  }

  @override
  Future<void> seek(Duration position) async {
    final resume = _playing;
    final finished = _queueFinished;
    final sources = List<AudioSource>.of(_sources);
    final index = _index;
    final preparing = setAudioSources(
      sources,
      initialIndex: index,
      initialPosition: position,
    );
    final command = _command, generation = _generation;
    await preparing;
    if (_disposed || _disposal != null || generation != _generation) return;
    if (finished) await finishQueue();
    if (resume && command == _command) await play();
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    await stop();
    _disposed = true;
    await _subscription.cancel();
    await Future.wait([
      _positions.close(),
      _sequences.close(),
      _states.close(),
      _errors.close(),
    ]);
  }
}
