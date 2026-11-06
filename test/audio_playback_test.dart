import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';

/// Emits sticky EOF, delayed loads, duplicate events and native errors like the
/// platform plugin. Filesystem and transport behavior are tested separately with
/// the real repository and a controlled Dio adapter.
class FakePlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final loadedSources = <AudioSource>[];
  final loadedPositions = <Duration?>[];
  int starts = 0, sourceLoads = 0, generation = 0;
  int failLoads = 0, failPlays = 0;
  bool active = false;
  ProcessingState state = ProcessingState.idle;
  Completer<void>? loadGate;
  Duration at = Duration.zero;
  @override
  LoopMode loopMode = LoopMode.off;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Duration get position => at;
  @override
  Duration get bufferedPosition => at;
  @override
  Duration? get duration => const Duration(seconds: 10);
  @override
  bool get playing => active;
  @override
  ProcessingState get processingState => state;
  @override
  Future<void> play() async {
    if (active) return;
    starts++;
    active = true;
    if (failPlays-- > 0) {
      errors.add(PlayerException(1, 'decoder', 0));
      return;
    }
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> stop() async {
    generation++;
    active = false;
    state = ProcessingState.idle;
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> pause() async {
    active = false;
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    at = position ?? Duration.zero;
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
    if (load != generation) throw StateError('Interrupted');
    if (failLoads-- > 0) throw PlayerException(1, 'decoder', 0);
    at = initialPosition ?? Duration.zero;
    state = ProcessingState.ready;
    states.add(PlayerState(active, state));
    return duration;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopMode = mode;
  }

  void complete() {
    state = ProcessingState.completed;
    states.add(PlayerState(active, state));
  }

  void buffering() {
    active = false;
    state = ProcessingState.buffering;
    states.add(PlayerState(false, state));
  }

  void fail() => errors.add(PlayerException(1, 'corrupt source', 0));
  @override
  Future<void> dispose() async {
    await states.close();
    await errors.close();
    await positions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ControlledRepository implements AudioRecordingRepository {
  final requested = <String>[];
  final urgentRequests = <String>[];
  final invalidated = <String>[];
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
    requested.add(key);
    if (urgent) urgentRequests.add(key);
    if (!urgent) {
      if (failPrefetch) {
        throw const AudioFailure(
          AudioFailureKind.connectivity,
          'Prefetch offline',
        );
      }
      return '/audio/$key.mp3';
    }
    cancelled.add(token);
    await gates[item.key]?.future;
    if (token.isCancelled) throw token.cancelError!;
    final count = remainingFailures[item.key] ?? 0;
    if (count > 0) {
      remainingFailures[item.key] = count - 1;
      throw failures[item.key] ??
          const AudioFailure(AudioFailureKind.connectivity, 'Offline');
    }
    onProgress?.call(1);
    return '/audio/$key.mp3';
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
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePlayer player;
  late ControlledRepository repo;
  late QuranAudioController c;
  setUp(() {
    player = FakePlayer();
    repo = ControlledRepository();
    c = QuranAudioController.forTesting(player: player, repository: repo);
  });
  tearDown(() async {
    await c.stop();
    c.dispose();
  });

  test(
    'starts after first recording and prefetches only next three distinct ayahs',
    () async {
      await c.playPlan(plan(surah: 2, from: 2, to: 286));
      expect(repo.urgentRequests, ['alafasy/2:2']);
      expect(repo.requested, [
        'alafasy/2:2',
        'alafasy/2:3',
        'alafasy/2:4',
        'alafasy/2:5',
      ]);
      expect(c.currentAyah, 2);
      expect(player.loadedSources.length, 1);
      player.complete();
      await flush();
      expect(c.currentAyah, 3);
    },
  );
  test(
    'a failed future prefetch never interrupts the current recording',
    () async {
      repo.failPrefetch = true;
      await c.playPlan(plan());
      await flush();
      expect(c.currentAyah, 2);
      expect(c.phase, QuranPlaybackPhase.playing);
      expect(c.error, isNull);
      expect(player.starts, 1);
    },
  );
  for (final count in [1, 3, 10]) {
    test(
      'finite range repeats $count times with bounded queues and reused definitions',
      () async {
        await c.playPlan(plan(from: 2, to: 3, count: count));
        for (var cycle = 1; cycle <= count; cycle++) {
          expect(c.currentRepeat, cycle);
          expect(c.currentAyah, 2);
          player.complete();
          await flush();
          expect(c.currentAyah, 3);
          player.complete();
          await flush();
        }
        expect(c.phase, QuranPlaybackPhase.completed);
        expect(player.starts, count * 2);
        expect(player.loadedSources.toSet().length, 2);
        expect(player.loopMode, LoopMode.off);
        await c.play();
        expect(c.currentAyah, 2);
        expect(player.active, isTrue);
      },
    );
  }
  test(
    'finite verse repeats and infinite verse do not loop the entire range',
    () async {
      await c.playPlan(
        plan(from: 2, to: 3, count: 3, repeat: AudioRepeatMode.ayah),
      );
      for (var i = 0; i < 6; i++) {
        expect(c.currentAyah, 2 + i ~/ 3);
        expect(c.currentRepeat, i % 3 + 1);
        player.complete();
        await flush();
      }
      expect(c.phase, QuranPlaybackPhase.completed);
      await c.playPlan(plan(count: null, repeat: AudioRepeatMode.ayah));
      for (var i = 0; i < 20; i++) {
        player.complete();
        await flush();
      }
      expect(c.currentAyah, 2);
      expect(c.currentRepeat, 21);
      expect(player.loadedSources.takeLast(20).toSet().length, 1);
      await c.seekNext();
      expect(c.currentAyah, 3);
      expect(c.currentRepeat, 1);
      await c.seekPrevious();
      expect(c.currentAyah, 2);
    },
  );
  test(
    'infinite range survives duplicate EOF and keeps logical cycles',
    () async {
      await c.playPlan(plan(from: 4, count: null));
      for (var i = 0; i < 15; i++) {
        player.complete();
        player.complete();
        await flush();
      }
      expect(c.currentRepeat, 16);
      expect(c.hasActivePlayback, isTrue);
      expect(player.loadedSources.toSet().length, 1);
    },
  );
  test(
    'download failure at boundary retries same ayah and repetition',
    () async {
      repo.remainingFailures['112:3'] = 2;
      await c.playPlan(plan(count: 3));
      player.complete();
      await flush();
      expect(c.currentAyah, 3);
      expect(c.currentRepeat, 1);
      expect(repo.urgentRequests.where((k) => k.endsWith('112:3')).length, 3);
      expect(player.starts, 2);
    },
  );
  test(
    'permanent 404 fails once with persistent Retry Skip Stop choices',
    () async {
      repo.remainingFailures['112:3'] = 1;
      repo.failures['112:3'] = const AudioFailure(
        AudioFailureKind.missing,
        '404',
      );
      await c.playPlan(plan());
      player.complete();
      await flush();
      expect(c.phase, QuranPlaybackPhase.failed);
      expect(c.currentItem!.ayah, 3);
      expect(c.hasActivePlayback, isTrue);
      expect(c.error, contains('112:3'));
      expect(repo.urgentRequests.where((k) => k.endsWith('112:3')).length, 1);
      await c.retry();
      expect(c.currentAyah, 3);
    },
  );
  test(
    'network recovery exhausts once and manual skip skips only the failing ayah',
    () async {
      repo.remainingFailures['112:3'] = 100;
      await c.playPlan(plan());
      player.complete();
      await flush();
      expect(c.phase, QuranPlaybackPhase.failed);
      expect(repo.urgentRequests.where((k) => k.endsWith('112:3')).length, 4);
      await c.seekNext();
      expect(c.currentAyah, 4);
    },
  );
  test(
    'decoder error invalidates only failing file and restores position/counters',
    () async {
      await c.playPlan(plan(count: 3));
      player.at = const Duration(seconds: 4);
      player.fail();
      await flush();
      expect(repo.invalidated, ['112:2']);
      expect(c.currentAyah, 2);
      expect(c.currentRepeat, 1);
      expect(player.loadedPositions.last, const Duration(seconds: 4));
      expect(c.error, isNull);
    },
  );
  test('repeated errors after successful loads are bounded too', () async {
    player.failPlays = 100;
    await c.playPlan(plan());
    await flush();
    expect(c.phase, QuranPlaybackPhase.failed);
    expect(player.starts, 4);
    expect(repo.invalidated.length, 3);
  });
  test('Stop during pending recovery prevents late autoplay', () async {
    await c.playPlan(plan());
    repo.gates['112:2'] = Completer<void>();
    player.fail();
    await flush();
    final starts = player.starts;
    final token = repo.cancelled.last;
    await c.stop();
    expect(c.phase, QuranPlaybackPhase.idle);
    expect(token.isCancelled, isTrue);
    repo.gates['112:2']!.complete();
    await flush();
    expect(player.starts, starts);
  });
  test(
    'Pause while preparing or buffering preserves intent after ready',
    () async {
      repo.gates['112:2'] = Completer<void>();
      final pending = c.playPlan(plan());
      await flush();
      await c.pause();
      repo.gates['112:2']!.complete();
      await pending;
      expect(c.playing, isFalse);
      expect(player.starts, 0);
      await c.play();
      player.buffering();
      await c.pause();
      player.state = ProcessingState.ready;
      player.states.add(PlayerState(false, player.state));
      expect(c.playing, isFalse);
      expect(c.hasActivePlayback, isTrue);
    },
  );
  test(
    'unexpected native pause at ready updates intent; buffering alone does not',
    () async {
      await c.playPlan(plan());
      player.buffering();
      expect(c.playing, isTrue);
      player.active = false;
      player.state = ProcessingState.ready;
      player.states.add(PlayerState(false, ProcessingState.ready));
      expect(c.playing, isFalse);
      expect(c.phase, QuranPlaybackPhase.paused);
      await c.play();
      expect(c.playing, isTrue);
    },
  );
  test('replacement reciter wins over old delayed preparation', () async {
    final gate = repo.gates['112:2'] = Completer<void>();
    final old = c.playPlan(plan());
    await flush();
    final oldToken = repo.cancelled.last;
    repo.gates.clear();
    await c.playPlan(plan(from: 3, reciter: quranReciters[1]));
    expect(oldToken.isCancelled, isTrue);
    // The previous request still has its own gate, released by its owner below.
    expect(c.plan!.reciter.id, 'sudais');
    expect(c.currentAyah, 3);
    // Stop cancellation is enough for real repository requests; complete fixture.
    await c.stop();
    // Avoid awaiting a deliberately uncooperative fake until the test releases it.
    gate.complete();
    await old;
  });
  test(
    'replacement during native loading cannot resurrect exhausted session',
    () async {
      player.loadGate = Completer<void>();
      final gate = player.loadGate!;
      final old = c.playPlan(plan());
      await flush();
      player.loadGate = null;
      final next = c.playPlan(plan(from: 3));
      gate.complete();
      await old;
      await next;
      expect(c.currentAyah, 3);
      expect(player.starts, 1);
      expect(c.error, isNull);
    },
  );
  test(
    'native load timeout enters bounded recovery and Stop remains available',
    () async {
      c.dispose();
      c = QuranAudioController.forTesting(
        player: player = FakePlayer(),
        repository: repo,
        loadTimeout: const Duration(milliseconds: 2),
      );
      player.loadGate = Completer<void>();
      await c.playPlan(plan());
      expect(c.phase, QuranPlaybackPhase.failed);
      expect(player.starts, 0);
      await c.stop();
      player.loadGate!.complete();
      await flush();
      expect(c.hasActivePlayback, isFalse);
    },
  );
  test(
    'background commands share cursor, pause intent and failure recovery',
    () async {
      final handler = QuranAudioHandler(c);
      await c.playPlan(plan(count: null, repeat: AudioRepeatMode.ayah));
      await handler.skipToNext();
      expect(c.currentAyah, 3);
      await handler.pause();
      expect(c.playing, isFalse);
      await handler.skipToPrevious();
      expect(c.currentAyah, isNull);
      await handler.play();
      expect(c.currentAyah, 2);
      expect(handler.mediaItem.value!.title, contains('112:2'));
      expect(handler.playbackState.value.playing, isTrue);
      await handler.stop();
      expect(c.phase, QuranPlaybackPhase.idle);
    },
  );
  for (final surah in [1, 9, 2]) {
    test(
      'introduction rules for surah $surah and numbering/highlighting',
      () async {
        await c.playPlan(plan(surah: surah, from: 1, to: 2));
        expect(c.isIntroduction, surah == 2);
        if (surah == 2) {
          expect(c.currentAyah, isNull);
          expect(c.currentItem!.label, contains('Bismillah'));
          await c.seekNext();
        }
        expect(c.currentAyah, 1);
      },
    );
  }
  test(
    'intro recovery/skip does not skip ayah one or repeat intro per verse',
    () async {
      repo.remainingFailures['112:bismillah'] = 100;
      await c.playPlan(plan(from: 1, count: 3, repeat: AudioRepeatMode.ayah));
      expect(c.phase, QuranPlaybackPhase.failed);
      expect(c.isIntroduction, isTrue);
      await c.seekNext();
      expect(c.currentAyah, 1);
      player.complete();
      await flush();
      expect(c.currentAyah, 1);
      expect(c.currentRepeat, 2);
      expect(
        repo.urgentRequests.where((k) => k.contains('bismillah')).length,
        4,
      );
    },
  );
  test('playlist order and introductions restart on range cycles', () async {
    await c.playPlan(plan(queue: [112, 1, 9, 114], count: 2));
    final observed = <String>[];
    for (var i = 0; i < 2 * (1 + 4 + 7 + 129 + 1 + 6); i++) {
      observed.add(c.currentItem!.key);
      player.complete();
      await flush();
    }
    expect(observed.take(6), [
      '112:bismillah',
      '112:1',
      '112:2',
      '112:3',
      '112:4',
      '1:1',
    ]);
    expect(observed.where((k) => k == '112:bismillah').length, 2);
    expect(observed.where((k) => k == '114:bismillah').length, 2);
    expect(observed, isNot(contains('9:bismillah')));
    expect(c.phase, QuranPlaybackPhase.completed);
  });
}

extension<T> on List<T> {
  Iterable<T> takeLast(int n) => skip(length - n);
}
