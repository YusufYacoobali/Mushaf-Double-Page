import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/everyayah_pcm_proof.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/progress/journey_tracking.dart';
import 'audio_test_fixtures.dart';

class Proof extends EveryAyahPcmProof {
  Proof()
    : super(
        path: '/synthetic/continuous.wav',
        sha256: '',
        sampleRate: 44100,
        rows: [
          for (var i = 0; i <= 10; i++)
            PcmProofOccurrence(
              i == 0 ? null : i,
              i * 44100,
              (i + 1) * 44100,
              'synthetic-$i',
            ),
        ],
      );
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<void> verify() async {
    await gate?.future;
    if (fail) throw StateError('corrupt proof');
  }
}

AudioPlaybackPlan selected({
  int? count = 1,
  AudioSourceMode mode = AudioSourceMode.range,
}) => AudioPlaybackPlan(
  reciter: quranReciters.firstWhere((r) => r.id == 'yasser_dussary'),
  surah: 55,
  fromAyah: 1,
  toAyah: 10,
  repeatCount: count,
  repeatMode: AudioRepeatMode.range,
  sourceMode: mode,
);
void main() {
  late FakePlayer player;
  late ControlledRepository repo;
  late QuranAudioController c;
  late Proof proof;
  final heard = <String>[];
  setUp(() {
    heard.clear();
    player = FakePlayer()..durationOverride = const Duration(seconds: 11);
    repo = ControlledRepository();
    proof = Proof();
    c = QuranAudioController.forTesting(
      player: player,
      repository: repo,
      resolveIntroduction: fixtureIntroduction,
      listeningTracker: ListeningTracker(
        onListen: heard.add,
        onSeconds: (_) {},
      ),
    );
    c.registerPcmProofForDevelopment(proof);
  });
  tearDown(() async {
    await c.stop();
    c.dispose();
  });
  void position(int ms) {
    player.at = Duration(milliseconds: ms);
    player.positions.add(player.at);
  }

  test(
    'autoplay uses one WAV across Bismillah and ten sample-clock ayahs',
    () async {
      await c.playPlan(selected());
      await flush();
      expect(c.usingPcmProof, isTrue);
      expect(c.audible, isTrue);
      expect(c.isIntroduction, isTrue);
      for (var i = 1; i <= 10; i++) {
        position(i * 1000);
        expect(c.currentAyah, i);
        expect(c.currentMediaItem!.duration, const Duration(seconds: 1));
      }
      expect(player.sourceLoads, 1);
      expect(player.appends, 0);
      expect(repo.requested, isEmpty);
      player.complete();
      await flush();
      expect(c.phase, QuranPlaybackPhase.completed);
    },
  );
  test(
    'Next Previous and relative seek keep the same native file while paused',
    () async {
      await c.playPlan(selected());
      await c.seekNext();
      expect(c.currentAyah, 1);
      await c.pause();
      await c.seekNext();
      expect(c.currentAyah, 2);
      await c.seekPrevious();
      expect(c.currentAyah, 1);
      await c.seek(const Duration(milliseconds: 250));
      expect(player.at.inMilliseconds, 1250);
      expect(c.playbackPosition.inMilliseconds, 250);
      expect(c.paused, isTrue);
      await c.play();
      expect(player.sourceLoads, 1);
    },
  );
  test(
    'Journey counts actual interval playback once and excludes introduction',
    () async {
      await c.playPlan(selected());
      for (var row = 0; row <= 10; row++) {
        for (var ms = 0; ms < 1000; ms += 50) {
          position(row * 1000 + ms);
        }
      }
      await c.pause();
      expect(heard, [for (var a = 1; a <= 10; a++) '55:$a']);
      await c.play();
      position(10999);
      expect(heard, hasLength(10));
    },
  );
  test('interruptions pause and never resume automatically', () async {
    final handler = QuranAudioHandler(c);
    final interruptions = StreamController<AudioInterruptionEvent>.broadcast(
      sync: true,
    );
    final noisy = StreamController<void>.broadcast(sync: true);
    handler.bindSessionEvents(
      becomingNoisy: noisy.stream,
      interruptions: interruptions.stream,
    );
    await c.playPlan(selected());
    position(5000);
    interruptions.add(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    await flush();
    interruptions.add(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    await flush();
    expect(c.paused, isTrue);
    expect(c.currentAyah, 5);
    await handler.play();
    expect(c.currentAyah, 5);
    await handler.dispose();
    await noisy.close();
    await interruptions.close();
  });
  test(
    'failure falls back once retaining ayah and pause intent without duplicate playback',
    () async {
      final p = selected();
      await c.playPlan(p);
      position(5000);
      await c.pause();
      player.fail();
      player.fail();
      await flush();
      expect(c.usingPcmProof, isFalse);
      expect(c.plan, same(p));
      expect(c.currentItem!.ayah, 5);
      expect(c.paused, isTrue);
      expect(repo.requested, isNotEmpty);
      expect(player.starts, 1);
    },
  );
  test(
    'verification failure ignores stale position and falls back at Bismillah',
    () async {
      proof.fail = true;
      player.at = const Duration(seconds: 6);
      await c.playPlan(selected());
      await flush();
      expect(c.usingPcmProof, isFalse);
      expect(c.isIntroduction, isTrue);
    },
  );
  test('Stop or replacement prevents stale proof autoplay', () async {
    proof.gate = Completer<void>();
    final pending = c.playPlan(selected());
    await flush();
    await c.stop();
    await c.playPlan(plan(from: 2));
    proof.gate!.complete();
    await pending;
    await flush();
    expect(c.usingPcmProof, isFalse);
    expect(c.plan!.surah, 112);
    expect(player.starts, 1);
  });
  test(
    'repeats, full surah and queues retain regular EveryAyah behavior',
    () async {
      for (final p in [
        selected(count: 3),
        selected(count: null),
        selected(mode: AudioSourceMode.surah),
        selected(mode: AudioSourceMode.playlist),
      ]) {
        await c.playPlan(p);
        await flush();
        expect(c.usingPcmProof, isFalse);
      }
    },
  );
}
