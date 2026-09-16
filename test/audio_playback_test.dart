import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';

// play() deliberately never resolves until stopped, just like the native player.
class FakePlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final indexes = StreamController<int?>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final plays = <Completer<void>>[];
  int starts = 0;
  int seeks = 0;
  int sourceLoads = 0;
  int sourceCount = 0;
  bool active = false;
  ProcessingState state = ProcessingState.idle;
  Completer<void>? seekGate;
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
    starts++;
    active = true;
    final completer = Completer<void>();
    plays.add(completer);
    return completer.future;
  }

  @override
  Future<void> stop() async {
    active = false;
    state = ProcessingState.idle;
    for (final c in plays) {
      if (!c.isCompleted) c.complete();
    }
  }

  @override
  Future<void> pause() async {
    active = false;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks++;
    await seekGate?.future;
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
    sourceLoads++;
    sourceCount = sources.length;
    state = ProcessingState.ready;
    return null;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  void complete() {
    state = ProcessingState.completed;
    states.add(PlayerState(active, state));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
      'range plays exactly $count cycles without waiting on play()',
      () async {
        final player = FakePlayer();
        final controller = QuranAudioController.forTesting(
          player: player,
          prepareSources: (p) async => [
            for (final v in p.uniqueVerses())
              AudioSource.uri(Uri.parse('https://example.test/${v.ayah}.mp3')),
          ],
        );
        await controller.playPlan(plan(count: count));
        expect(controller.preparing, isFalse);
        for (var cycle = 1; cycle <= count; cycle++) {
          expect(controller.currentRepeat, cycle);
          player.complete();
          await flush();
        }
        expect(player.starts, count);
        expect(player.seeks, count - 1);
        expect(player.sourceLoads, 1);
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
  test('stop during repeat seek prevents restart', () async {
    final player = FakePlayer();
    final controller = QuranAudioController.forTesting(
      player: player,
      prepareSources: (_) async => [],
    );
    await controller.playPlan(plan());
    player.seekGate = Completer<void>();
    player.complete();
    await controller.stop();
    player.seekGate!.complete();
    await flush();
    expect(player.starts, 1);
  });
  test(
    'ten cycles retain active session and ayah across pending seeks',
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
        player.seekGate = Completer<void>();
        player.complete();
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
        // Duplicate completion during the seek must not finish the next cycle.
        player.complete();
        player.seekGate!.complete();
        await flush();
        expect(controller.currentRepeat, cycle + 1);
        expect(controller.currentAyah, 1);
        expect(observations, everyElement(isTrue));
        player.indexes.add(1);
        expect(controller.currentAyah, 2);
      }
      expect(player.starts, 10);
      expect(player.seeks, 9);
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
      expect(controller.hasActivePlayback, isFalse);
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
