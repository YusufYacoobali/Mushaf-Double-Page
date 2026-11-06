import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'audio_test_fixtures.dart';
export 'audio_test_fixtures.dart';

void main() {
  late FakePlayer player;
  late ControlledRepository repo;
  late QuranAudioController c;
  setUp(() {
    player = FakePlayer();
    repo = ControlledRepository();
    c = QuranAudioController.forTesting(
      player: player,
      repository: repo,
      resolveIntroduction: fixtureIntroduction,
    );
  });
  tearDown(() async {
    await c.stop();
    c.dispose();
  });
  test(
    'cached consecutive ayahs use one initial queue and automatic transitions',
    () async {
      await c.playPlan(plan(surah: 2, from: 2, to: 20));
      await flush();
      expect(player.queue.length, 4);
      expect(repo.requested.first, 'alafasy/2:2');
      final pause = player.pauses, stop = player.stops;
      for (var a = 2; a < 15; a++) {
        expect(c.currentAyah, a);
        player.advance();
        await flush();
        expect(player.sourceLoads, 1);
        expect(player.pauses, pause);
        expect(player.stops, stop);
        expect(c.nativeQueueLength, lessThanOrEqualTo(6));
      }
      expect(c.currentAyah, 15);
      expect(player.removals, greaterThan(0));
    },
  );
  test(
    'removing consumed entries keeps the actual occurrence and playhead',
    () async {
      await c.playPlan(plan(surah: 2, from: 2, to: 20));
      await flush();
      player.advance();
      await flush();
      player.at = const Duration(seconds: 3);
      player.advance();
      player.at = const Duration(seconds: 4);
      final id = c.currentOccurrence!.occurrenceId;
      await flush();
      expect(c.currentOccurrence!.occurrenceId, id);
      expect(c.currentAyah, 4);
      expect(player.position, const Duration(seconds: 4));
      expect(c.currentRepeat, 1);
    },
  );
  test(
    'native queue and retained sources remain bounded for 2500 transitions',
    () async {
      await c.playPlan(plan(from: 2, to: 3, count: null));
      await flush();
      for (var i = 0; i < 2500; i++) {
        expect(c.currentAyah, 2 + i % 2);
        expect(c.currentRepeat, 1 + i ~/ 2);
        player.advance();
        await flush();
        expect(c.nativeQueueLength, lessThanOrEqualTo(6));
        expect(c.retainedSourceCount, lessThanOrEqualTo(6));
      }
      expect(player.sourceLoads, 1);
      expect(player.maxQueue, lessThanOrEqualTo(6));
    },
  );
  for (final repeat in AudioRepeatMode.values) {
    test(
      'finite ${repeat.name} cycles advance exactly once per actual occurrence',
      () async {
        await c.playPlan(plan(from: 2, to: 3, count: 3, repeat: repeat));
        await flush();
        for (var i = 0; i < 6; i++) {
          expect(
            c.currentAyah,
            repeat == AudioRepeatMode.range ? 2 + i % 2 : 2 + i ~/ 3,
          );
          expect(
            c.currentRepeat,
            repeat == AudioRepeatMode.range ? 1 + i ~/ 2 : 1 + i % 3,
          );
          player.advance();
          await flush();
        }
        expect(c.phase, QuranPlaybackPhase.completed);
        expect(player.sourceLoads, 1);
        await c.play();
        expect(c.hasActivePlayback, isTrue);
      },
    );
  }
  test(
    'infinite verse Next/Previous select logical ayahs, not repeated copies',
    () async {
      await c.playPlan(plan(count: null, repeat: AudioRepeatMode.ayah));
      await flush();
      for (var i = 0; i < 15; i++) {
        player.advance();
        await flush();
      }
      expect(c.currentAyah, 2);
      expect(c.currentRepeat, 16);
      await c.seekNext();
      await flush();
      expect(c.currentAyah, 3);
      expect(c.currentRepeat, 1);
      await c.seekPrevious();
      expect(c.currentAyah, 2);
    },
  );
  test(
    'slow next recording leaves current healthy then buffers at genuine exhaustion',
    () async {
      final gate = repo.gates['112:3'] = Completer<void>();
      await c.playPlan(plan());
      await flush();
      expect(c.currentAyah, 2);
      expect(c.phase, QuranPlaybackPhase.playing);
      final loads = player.sourceLoads;
      player.advance();
      await flush();
      expect(c.hasActivePlayback, isTrue);
      expect(c.phase, QuranPlaybackPhase.buffering);
      expect(player.sourceLoads, loads);
      await c.pause();
      gate.complete();
      await flush();
      expect(c.currentItem!.ayah, 3);
      expect(c.playing, isFalse);
      expect(player.sourceLoads, loads + 1);
      await c.play();
      expect(c.currentAyah, 3);
    },
  );
  test(
    'EOF while an append is pending resumes the exact next occurrence, paused',
    () async {
      final gate = player.appendGate = Completer<void>();
      await c.playPlan(plan());
      await flush();
      player.advance();
      await c.pause();
      await flush();
      gate.complete();
      await flush();
      expect(c.currentItem!.ayah, 3);
      expect(c.playing, isFalse);
      await c.play();
      expect(c.currentAyah, 3);
      expect(c.currentRepeat, 1);
      player.advance();
      await flush();
      expect(c.currentAyah, 4);
    },
  );
  test(
    'Stop/replacement during delayed native setup cannot resurrect an old window',
    () async {
      final gate = player.loadGate = Completer<void>();
      final old = c.playPlan(plan());
      await flush();
      player.loadGate = null;
      final newer = c.playPlan(plan(from: 3));
      gate.complete();
      await old;
      await newer;
      await flush();
      expect(c.currentAyah, 3);
      expect(player.starts, 1);
      await c.stop();
      expect(c.currentItem, isNull);
    },
  );
  test(
    'future download failure cannot interrupt current, skip, or consume repetition',
    () async {
      repo.remainingFailures['112:3'] = 2;
      await c.playPlan(plan(count: 3));
      await flush();
      expect(c.currentAyah, 2);
      expect(c.error, isNull);
      expect(player.sourceLoads, 1);
      player.advance();
      await flush();
      expect(c.currentAyah, 3);
      expect(c.currentRepeat, 1);
      expect(c.error, isNull);
    },
  );
  test(
    'permanent missing future recording fails at its boundary, with explicit retry',
    () async {
      repo.remainingFailures['112:3'] = 1;
      repo.failures['112:3'] = const AudioFailure(
        AudioFailureKind.missing,
        '404',
      );
      await c.playPlan(plan());
      await flush();
      expect(c.error, isNull);
      player.advance();
      await flush();
      expect(c.phase, QuranPlaybackPhase.failed);
      expect(c.currentItem!.ayah, 3);
      await c.retry();
      await flush();
      expect(c.currentAyah, 3);
      expect(c.currentRepeat, 1);
    },
  );
  test('future decoder error repairs its recording only at boundary', () async {
    await c.playPlan(plan());
    await flush();
    player.at = const Duration(seconds: 4);
    final id = c.currentOccurrence!.occurrenceId;
    final pauses = player.pauses;
    player.fail(sourceIndex: 1);
    await flush();
    expect(repo.invalidated, isEmpty);
    expect(c.currentAyah, 2);
    expect(player.pauses, pauses);
    expect(c.currentOccurrence!.occurrenceId, id);
    expect(player.position, const Duration(seconds: 4));
    player.advance();
    await flush();
    expect(repo.invalidated, ['112:3']);
    expect(c.currentAyah, 3);
  });
  test(
    'a fatal future-source error reloads healthy current without deleting its cache',
    () async {
      await c.playPlan(plan());
      await flush();
      player.state = ProcessingState.idle;
      player.active = false;
      player.at = const Duration(seconds: 3);
      player.fail(sourceIndex: 1);
      await flush();
      expect(c.currentAyah, 2);
      expect(repo.invalidated, isNot(contains('112:2')));
      expect(player.loadedPositions.last, const Duration(seconds: 3));
      player.advance();
      await flush();
      expect(c.currentAyah, 3);
      expect(repo.invalidated, contains('112:3'));
    },
  );
  test(
    'current decoder recovery retains identity, position and repetition',
    () async {
      await c.playPlan(plan(count: 3));
      await flush();
      final id = c.currentOccurrence!.occurrenceId;
      player.at = const Duration(seconds: 4);
      player.fail();
      await flush();
      expect(repo.invalidated, ['112:2']);
      expect(c.currentOccurrence!.occurrenceId, id);
      expect(player.loadedPositions.last, const Duration(seconds: 4));
      expect(c.currentRepeat, 1);
    },
  );
  test(
    'bounded retries and manual Skip never skip a healthy numbered ayah',
    () async {
      repo.remainingFailures['112:3'] = 100;
      await c.playPlan(plan());
      await flush();
      player.advance();
      await flush();
      expect(c.phase, QuranPlaybackPhase.failed);
      expect(repo.requested.where((k) => k == 'alafasy/112:3').length, 4);
      await c.seekNext();
      expect(c.currentAyah, 4);
    },
  );
  test('repeated errors after successful native loads are bounded', () async {
    player.failPlays = 100;
    await c.playPlan(plan());
    await flush();
    expect(c.phase, QuranPlaybackPhase.failed);
    expect(player.starts, 4);
  });
  test(
    'Stop and replacement invalidate late downloads and pending appends',
    () async {
      final gate = player.appendGate = Completer<void>();
      await c.playPlan(plan());
      await flush();
      final loads = player.sourceLoads;
      await c.stop();
      gate.complete();
      await flush();
      expect(c.phase, QuranPlaybackPhase.idle);
      expect(player.sourceLoads, loads);
      expect(player.queue.length, 1);
      player.appendGate = null;
      final download = repo.gates['112:2'] = Completer<void>();
      final old = c.playPlan(plan());
      await flush();
      repo.gates.clear();
      await c.playPlan(plan(from: 3, reciter: quranReciters[1]));
      download.complete();
      await old;
      await flush();
      expect(c.plan!.reciter.id, 'sudais');
      expect(c.currentAyah, 3);
    },
  );
  test(
    'Next invalidates a slow prefetch; its late append cannot change the new cursor',
    () async {
      final gate = repo.gates['112:3'] = Completer<void>();
      await c.playPlan(plan());
      await flush();
      repo.gates.clear();
      await c.seekNext();
      gate.complete();
      await flush();
      expect(c.currentAyah, 3);
      expect(
        player.sequenceState.currentSource!.tag,
        (isA<QuranAudioOccurrence>()),
      );
      expect(
        (player.sequenceState.currentSource!.tag as QuranAudioOccurrence)
            .sessionGeneration,
        c.playbackSessionId,
      );
    },
  );
  test(
    'native stale state and index-shift notifications do not advance current occurrence',
    () async {
      await c.playPlan(plan(surah: 2, from: 2, to: 20));
      await flush();
      player.advance();
      await flush();
      final old = player.sequenceState;
      player.advance();
      await flush();
      final id = c.currentOccurrence!.occurrenceId;
      player.sequences.add(old);
      expect(c.currentOccurrence!.occurrenceId, id);
    },
  );
  test(
    'background commands and seeking use the authoritative cursor',
    () async {
      final handler = QuranAudioHandler(c);
      await c.playPlan(plan(count: null, repeat: AudioRepeatMode.ayah));
      await flush();
      await handler.skipToNext();
      expect(c.currentAyah, 3);
      await handler.pause();
      expect(c.playing, isFalse);
      await handler.seek(const Duration(seconds: 3));
      expect(player.position, const Duration(seconds: 3));
      await handler.play();
      expect(handler.playbackState.value.playing, isTrue);
      expect(handler.mediaItem.value!.title, contains('112:3'));
      await handler.stop();
      expect(c.phase, QuranPlaybackPhase.idle);
    },
  );
  test(
    'playlist order, introductions and range cycles follow native transitions',
    () async {
      await c.playPlan(plan(queue: [112, 1, 114], count: 2));
      await flush();
      final observed = <String>[];
      for (var i = 0; i < 2 * (1 + 4 + 7 + 1 + 6); i++) {
        observed.add('${c.currentItem!.key}/${c.currentRepeat}');
        player.advance();
        await flush();
      }
      expect(observed.take(6), [
        '112:bismillah/1',
        '112:1/1',
        '112:2/1',
        '112:3/1',
        '112:4/1',
        '1:1/1',
      ]);
      expect(observed.where((s) => s.startsWith('112:bismillah')).length, 2);
      expect(c.phase, QuranPlaybackPhase.completed);
      expect(player.sourceLoads, 1);
    },
  );
  for (final surah in [1, 9, 2]) {
    test(
      'introduction special cases for surah $surah preserve numbered identity',
      () async {
        await c.playPlan(plan(surah: surah, from: 1, to: 2));
        await flush();
        expect(c.isIntroduction, surah == 2);
        if (surah == 2) {
          expect(c.currentAyah, isNull);
          await c.seekNext();
        }
        expect(c.currentAyah, 1);
      },
    );
  }
  test(
    'introduction failure skip applies across session repeats and preserves ayah one',
    () async {
      repo.remainingFailures['112:bismillah'] = 100;
      await c.playPlan(plan(from: 1, to: 2, count: 2));
      expect(c.phase, QuranPlaybackPhase.failed);
      await c.seekNext();
      await flush();
      expect(c.currentAyah, 1);
      for (var i = 0; i < 4; i++) {
        player.advance();
        await flush();
      }
      expect(c.phase, QuranPlaybackPhase.completed);
      expect(repo.requested.where((k) => k.contains('bismillah')).length, 4);
    },
  );
}
