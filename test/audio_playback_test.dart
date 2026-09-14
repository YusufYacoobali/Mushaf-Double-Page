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
