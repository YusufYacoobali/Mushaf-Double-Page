import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';

// Models just_audio's sticky playing flag at EOF and no-op play() when true.
// An exhausted queue cannot become audible again without a fresh source load.
class FakePlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast();
  final indexes = StreamController<int?>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final plays = <Completer<void>>[];
  final loadedSources = <List<AudioSource>>[];
  int starts = 0;
  int audibleStarts = 0;
  int seeks = 0;
  int sourceLoads = 0;
  int sourceCount = 0;
  int _loadGeneration = 0;
  bool active = false;
  bool decoderReady = false;
  ProcessingState state = ProcessingState.idle;
  Completer<void>? loadGate;
  @override
  LoopMode loopMode = LoopMode.off;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<int?> get currentIndexStream => indexes.stream;
  @override
  Stream<PlayerException> get errorStream => errors.stream;
  @override
  bool get playing => active;
  @override
  ProcessingState get processingState => state;
  @override
  Future<void> play() {
    if (active) return Future<void>.value();
    starts++;
    if (decoderReady) audibleStarts++;
    active = true;
    states.add(PlayerState(active, state));
    final completer = Completer<void>();
    plays.add(completer);
    return completer.future;
  }

  void _finishPlayRequests() {
    for (final c in plays) {
      if (!c.isCompleted) c.complete();
    }
  }

  @override
  Future<void> stop() async {
    _loadGeneration++;
    active = false;
    state = ProcessingState.idle;
    _finishPlayRequests();
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> pause() async {
    if (!active) return;
    active = false;
    _finishPlayRequests();
    states.add(PlayerState(active, state));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks++;
    state = ProcessingState.ready;
    states.add(PlayerState(active, state));
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    final generation = ++_loadGeneration;
    sourceLoads++;
    sourceCount = sources.length;
    loadedSources.add(List.of(sources));
    await loadGate?.future;
    if (generation != _loadGeneration) throw StateError('Loading interrupted');
    decoderReady = true;
    state = ProcessingState.ready;
    indexes.add(initialIndex ?? 0);
    states.add(PlayerState(active, state));
    return null;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopMode = mode;
  }

  void complete() {
    decoderReady = false;
    state = ProcessingState.completed;
    _finishPlayRequests();
    states.add(PlayerState(active, state));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<List<AudioSource>> sources(AudioPlaybackPlan p) async => [
  for (final v
      in p.repeatMode == AudioRepeatMode.range
          ? p.uniqueVerses()
          : p.playbackVerses())
    AudioSource.uri(Uri.parse('https://example.test/${v.surah}/${v.ayah}.mp3')),
];

AudioPlaybackPlan plan({int? count = 10}) => AudioPlaybackPlan(
  reciter: quranReciters.first,
  surah: 112,
  fromAyah: 1,
  toAyah: 4,
  repeatCount: count,
  repeatMode: AudioRepeatMode.range,
  sourceMode: AudioSourceMode.surah,
);
Future<void> flush() => Future<void>.delayed(Duration.zero);
void main() {
  for (final count in [1, 3, 5, 10]) {
    test(
      'range decodes exactly $count cycles using fresh native queues',
      () async {
        final player = FakePlayer();
        final controller = QuranAudioController.forTesting(
          player: player,
          prepareSources: sources,
        );
        await controller.playPlan(plan(count: count));
        expect(controller.preparing, isFalse);
        for (var cycle = 1; cycle <= count; cycle++) {
          expect(controller.currentRepeat, cycle);
          player.complete();
          await flush();
        }
        expect(player.starts, count);
        expect(player.audibleStarts, count);
        expect(player.active, isFalse);
        expect(controller.hasActivePlayback, isFalse);
        expect(player.seeks, 0);
        expect(player.sourceLoads, count);
        expect(player.loopMode, LoopMode.off);
        final sourceIds = player.loadedSources.expand((s) => s);
        expect(sourceIds.toSet().length, 4);
        expect(player.sourceCount, 4);
        await controller.stop();
      },
    );
  }
  test('infinite recovery remains available after many completions', () async {
    final player = FakePlayer();
    final controller = QuranAudioController.forTesting(
      player: player,
      prepareSources: (_) async => [],
    );
    await controller.playPlan(plan(count: null));
    for (var i = 0; i < 12; i++) {
      player.complete();
      await flush();
    }
    expect(player.starts, 13);
    expect(player.audibleStarts, 13);
    expect(player.sourceLoads, 13);
    expect(controller.currentRepeat, 13);
    await controller.stop();
  });
  test('stop during preparation prevents late autoplay', () async {
    final player = FakePlayer();
    final preparation = Completer<List<AudioSource>>();
    final controller = QuranAudioController.forTesting(
      player: player,
      prepareSources: (_) => preparation.future,
    );
    final pending = controller.playPlan(plan());
    await flush();
    await controller.stop();
    preparation.complete([]);
    await pending;
    expect(player.starts, 0);
    expect(controller.preparing, isFalse);
  });
  test('stop during repeat loading prevents restart', () async {
    final player = FakePlayer();
    final controller = QuranAudioController.forTesting(
      player: player,
      prepareSources: (_) async => [],
    );
    await controller.playPlan(plan());
    player.loadGate = Completer<void>();
    player.complete();
    await controller.stop();
    player.loadGate!.complete();
    await flush();
    expect(player.starts, 1);
  });
  test(
    'ten cycles retain active session and ayah across native queue reloads',
    () async {
      final player = FakePlayer();
      final controller = QuranAudioController.forTesting(
        player: player,
        prepareSources: (_) async => [],
      );
      await controller.playPlan(plan());
      final observations = <bool>[];
      controller.addListener(
        () => observations.add(controller.hasActivePlayback),
      );
      for (var cycle = 1; cycle <= 10; cycle++) {
        player.indexes.add(3);
        expect(controller.currentSurah, 112);
        expect(controller.currentAyah, 4);
        observations.clear();
        player.loadGate = Completer<void>();
        player.complete();
        await flush();
        if (cycle == 10) {
          expect(controller.hasActivePlayback, isFalse);
          expect(controller.currentAyah, isNull);
          break;
        }
        expect(controller.hasActivePlayback, isTrue);
        expect(controller.currentAyah, 4);
        // Native metadata/indexes may momentarily be unavailable at a repeat edge.
        player.indexes.add(null);
        expect(controller.currentAyah, 4);
        // Duplicate EOF during reload must not skip or finish the next cycle.
        player.complete();
        player.loadGate!.complete();
        await flush();
        expect(controller.currentRepeat, cycle + 1);
        expect(controller.currentAyah, 1);
        expect(observations, everyElement(isTrue));
        player.indexes.add(1);
        expect(controller.currentAyah, 2);
      }
      expect(player.starts, 10);
      expect(player.audibleStarts, 10);
      expect(player.seeks, 0);
      expect(player.sourceLoads, 10);
      await controller.stop();
    },
  );

  test(
    'pause and temporary processing states keep the session; stop clears it',
    () async {
      final player = FakePlayer();
      final controller = QuranAudioController.forTesting(
        player: player,
        prepareSources: (_) async => [],
      );
      await controller.playPlan(plan());
      player.indexes.add(2);
      await controller.togglePlayPause();
      expect(controller.playing, isFalse);
      expect(controller.hasActivePlayback, isTrue);
      expect(controller.currentAyah, 3);
      player.state = ProcessingState.buffering;
      player.states.add(PlayerState(false, player.state));
      player.indexes.add(null);
      expect(controller.currentAyah, 3);
      await controller.stop();
      expect(controller.hasActivePlayback, isFalse);
      expect(controller.currentAyah, isNull);
      player.complete();
      await flush();
      expect(player.starts, 1);
    },
  );

  test(
    'queue verse identity survives repeats across surah boundaries',
    () async {
      final player = FakePlayer();
      final controller = QuranAudioController.forTesting(
        player: player,
        prepareSources: (_) async => [],
      );
      await controller.playPlan(
        AudioPlaybackPlan(
          reciter: quranReciters.first,
          surah: 112,
          fromAyah: 1,
          toAyah: 4,
          repeatCount: 3,
          repeatMode: AudioRepeatMode.range,
          sourceMode: AudioSourceMode.playlist,
          surahQueue: [112, 114],
        ),
      );
      player.indexes.add(4);
      expect((controller.currentSurah, controller.currentAyah), (114, 1));
      player.complete();
      await flush();
      expect((controller.currentSurah, controller.currentAyah), (112, 1));
      player.indexes.add(9);
      expect((controller.currentSurah, controller.currentAyah), (114, 6));
      await controller.stop();
    },
  );

  test(
    'verse repeat reports the correct ayah and repetition without source tags',
    () async {
      final player = FakePlayer();
      final controller = QuranAudioController.forTesting(
        player: player,
        prepareSources: (_) async => [],
      );
      await controller.playPlan(
        AudioPlaybackPlan(
          reciter: quranReciters.first,
          surah: 112,
          fromAyah: 1,
          toAyah: 2,
          repeatCount: 3,
          repeatMode: AudioRepeatMode.ayah,
          sourceMode: AudioSourceMode.range,
        ),
      );
      for (var index = 0; index < 6; index++) {
        player.indexes.add(index);
        expect(controller.currentAyah, index ~/ 3 + 1);
        expect(controller.currentRepeat, index % 3 + 1);
        expect(controller.hasActivePlayback, isTrue);
      }
      player.complete();
      await flush();
      expect(controller.hasActivePlayback, isFalse);
      await controller.stop();
    },
  );

  test(
    'pause during repeat loading survives completion and resumes audibly',
    () async {
      final player = FakePlayer();
      final controller = QuranAudioController.forTesting(
        player: player,
        prepareSources: sources,
      );
      await controller.playPlan(plan(count: 3));
      player.loadGate = Completer<void>();
      player.complete();
      await flush();
      expect(controller.playing, isTrue);
      await controller.togglePlayPause();
      expect(controller.playing, isFalse);
      player.loadGate!.complete();
      await flush();
      expect(controller.currentRepeat, 2);
      expect(player.starts, 1);
      expect(controller.hasActivePlayback, isTrue);
      await controller.togglePlayPause();
      expect(player.audibleStarts, 2);
      await controller.stop();
    },
  );

  test(
    'reload error ends the session instead of leaving silent play controls',
    () async {
      final player = FakePlayer();
      final controller = QuranAudioController.forTesting(
        player: player,
        prepareSources: sources,
      );
      await controller.playPlan(plan());
      player.loadGate = Completer<void>();
      player.complete();
      await flush();
      player.loadGate!.completeError(StateError('unreadable cached source'));
      await flush();
      expect(controller.hasActivePlayback, isFalse);
      expect(controller.playing, isFalse);
      expect(controller.errorKind, QuranAudioErrorKind.playback);
      expect(player.active, isFalse);
    },
  );

  test(
    'replacement plan wins over a delayed native load of an old repeat',
    () async {
      final player = FakePlayer();
      final delayed = Completer<void>();
      final controller = QuranAudioController.forTesting(
        player: player,
        prepareSources: sources,
      );
      await controller.playPlan(plan());
      player.loadGate = delayed;
      player.complete();
      await flush();
      player.loadGate = null;
      await controller.playPlan(plan(count: 5));
      delayed.complete();
      await flush();
      expect(controller.plan!.repeatCount, 5);
      expect(controller.currentRepeat, 1);
      expect(player.sourceLoads, 3);
      expect(player.audibleStarts, 2);
      expect(controller.error, isNull);
      await controller.stop();
    },
  );

  test(
    'replaying a finished plan reloads rather than seeking an exhausted queue',
    () async {
      final player = FakePlayer();
      final controller = QuranAudioController.forTesting(
        player: player,
        prepareSources: sources,
      );
      await controller.playPlan(plan(count: 1));
      player.complete();
      await flush();
      expect(controller.hasActivePlayback, isFalse);
      await controller.togglePlayPause();
      expect(player.audibleStarts, 2);
      expect(player.sourceLoads, 2);
      expect(player.seeks, 0);
      await controller.stop();
    },
  );

  test('queue follows selection order and repeats across surah boundaries', () {
    final queue = AudioPlaybackPlan(
      reciter: quranReciters.first,
      surah: 1,
      fromAyah: 1,
      toAyah: 7,
      repeatCount: 3,
      repeatMode: AudioRepeatMode.range,
      sourceMode: AudioSourceMode.playlist,
      surahQueue: [114, 112],
    );
    final verses = queue.playbackVerses();
    expect(queue.uniqueAyahCount, 10);
    expect(verses.length, 30);
    expect(verses[0].surah, 114);
    expect(verses[6].surah, 112);
    expect(verses[10].surah, 114);
    expect(verses[10].cycle, 2);
  });
}
