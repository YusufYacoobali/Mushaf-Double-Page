import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mushaf_two_page/logic/mp3quran_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/audio_page_follower.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/progress/journey_tracking.dart';
import 'audio_test_fixtures.dart';
import 'audio_repository_test.dart' show TestTransport;

// Synthetic intervals and payload: these test behavior, not Quran content.
final payload = Uint8List.fromList(List.generate(256, (i) => i));
Mp3QuranManifest manifest({List<Mp3QuranInterval>? intervals}) =>
    Mp3QuranManifest(
      sha256: crypto.sha256.convert(payload).toString(),
      bytes: payload.length,
      durationMs: 34000,
      intervals:
          intervals ??
          [
            const Mp3QuranInterval(0, 1000, 2000),
            for (var a = 1; a <= 30; a++)
              Mp3QuranInterval(a, (a + 2) * 1000, (a + 2) * 1000 + 800),
          ],
    );
AudioPlaybackPlan selection({
  int? count = 1,
  int surah = 67,
  Reciter? reciter,
  AudioRepeatMode repeat = AudioRepeatMode.range,
  AudioSourceMode mode = AudioSourceMode.surah,
}) => AudioPlaybackPlan(
  reciter: reciter ?? quranReciters.first,
  surah: surah,
  fromAyah: 1,
  toAyah: 30,
  repeatCount: count,
  repeatMode: repeat,
  sourceMode: mode,
);

class ContinuousPlayer extends FakePlayer {
  bool failSeek = false;
  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (failSeek) throw StateError('seek failed');
    await super.seek(position, index: index);
    state = ProcessingState.ready;
    states.add(PlayerState(active, state));
  }
}

class PilotRepository extends Mp3QuranRepository {
  PilotRepository({bool available = true})
    : super(manifest: available ? manifest() : null);
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<String> recording(
    CancelToken token, {
    void Function(double)? onProgress,
  }) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('unavailable');
    return '/mp3quran/067.mp3';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PageAyahIndex.load);
  group('manifest and routing', () {
    test('only Alafasy Al-Mulk full-surah range repetition qualifies', () {
      expect(Mp3QuranPilot.supports(selection(count: null)), isTrue);
      for (final p in [
        selection(surah: 66),
        selection(reciter: quranReciters[1]),
        selection(repeat: AudioRepeatMode.ayah),
        selection(mode: AudioSourceMode.range),
        selection(mode: AudioSourceMode.playlist),
      ]) {
        expect(Mp3QuranPilot.supports(p), isFalse);
      }
      expect(Mp3QuranPilot.verifiedManifest, isNotNull);
    });
    test('incomplete, reordered and overlapping timings are rejected', () {
      final rows = manifest().intervals;
      expect(
        () => manifest(intervals: rows.take(30).toList()),
        throwsArgumentError,
      );
      expect(
        () => manifest(intervals: rows.reversed.toList()),
        throwsArgumentError,
      );
      expect(
        () => manifest(intervals: [...rows, rows.last]),
        throwsArgumentError,
      );
      expect(
        () => manifest(
          intervals: [const Mp3QuranInterval(0, 0, 4000), ...rows.skip(1)],
        ),
        throwsArgumentError,
      );
    });
    test(
      'bundled manifest matches the exact recording audit and every supplied boundary',
      () {
        final m = Mp3QuranPilot.verifiedManifest!;
        final audit =
            jsonDecode(
                  File(
                    'docs/mp3quran-alafasy-evidence/content-audit.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(m.sha256, audit['recordingSha256']);
        expect(m.bytes, audit['bytes']);
        expect(m.durationMs, (audit['decodedDurationMs'] as num).round());
        expect(audit['allIntervalsIdentifyExpectedAyah'], isTrue);
        final clips = (audit['clips'] as List)
            .where((c) => c['ayah'] >= 0)
            .toList();
        expect(m.intervals, hasLength(31));
        for (var i = 0; i < clips.length; i++) {
          final row = clips[i];
          final interval = m.intervals[i];
          expect(
            [interval.ayah, interval.startMs, interval.endMs],
            [row['ayah'], row['startMs'], row['endMs']],
          );
          expect(
            m.at(Duration(milliseconds: interval.startMs))!.ayah,
            interval.ayah,
          );
          expect(
            m.at(Duration(milliseconds: interval.endMs - 1))!.ayah,
            interval.ayah,
          );
          expect(m.at(Duration(milliseconds: interval.endMs)), isNull);
        }
        expect(m.at(const Duration(milliseconds: 7264)), isNull);
        expect(m.at(const Duration(milliseconds: 7265))!.ayah, 0);
        expect(m.at(const Duration(milliseconds: 206570))!.ayah, 15);
        expect(m.at(const Duration(milliseconds: 437630))!.ayah, 30);
      },
    );
    test('exact half-open intervals never fill silence gaps or tail', () {
      final m = manifest();
      expect(m.at(const Duration(milliseconds: 999)), isNull);
      expect(m.at(const Duration(seconds: 1))!.ayah, 0);
      expect(m.at(const Duration(seconds: 2)), isNull);
      expect(m.at(const Duration(seconds: 3))!.ayah, 1);
      expect(m.at(const Duration(milliseconds: 3800)), isNull);
      expect(m.at(const Duration(milliseconds: 32799))!.ayah, 30);
      expect(m.at(const Duration(milliseconds: 32800)), isNull);
    });
  });

  group('cache', () {
    late Directory root;
    late TestTransport transport;
    late Mp3QuranRepository repo;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('mp3quran-test-');
      transport = TestTransport(payload);
      repo = Mp3QuranRepository(
        dio: Dio()..httpClientAdapter = transport,
        directory: () async => root,
        manifest: manifest(),
      );
    });
    tearDown(() => root.delete(recursive: true));
    test('downloads once, then verifies and reuses offline cache', () async {
      final path = await repo.recording(CancelToken());
      expect(path, contains('/mp3quran/mishary-alafasy/r1/'));
      transport.status = 503;
      expect(await repo.recording(CancelToken()), path);
      expect(transport.calls, 1);
      expect(await File(path).readAsBytes(), payload);
    });
    test(
      'same-size corruption forces a download; bad payload is never published',
      () async {
        final path = await repo.recording(CancelToken());
        final corrupt = Uint8List(payload.length);
        await File(path).writeAsBytes(corrupt);
        transport.payloads['067.mp3'] = corrupt;
        await expectLater(repo.recording(CancelToken()), throwsStateError);
        expect(transport.calls, 2);
        expect(
          root
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.part')),
          isEmpty,
        );
        transport.payloads.clear();
        expect(await repo.recording(CancelToken()), path);
        expect(await File(path).readAsBytes(), payload);
      },
    );
    test('download cancellation removes partial data', () async {
      final gate = transport.gates['067.mp3'] = Completer<void>();
      final token = CancelToken();
      final download = repo.recording(token);
      final failure = expectLater(download, throwsA(isA<DioException>()));
      while (transport.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      token.cancel();
      gate.complete();
      await failure;
      expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
    });
  });

  group('continuous controller', () {
    late FakePlayer player;
    late ControlledRepository everyAyah;
    late PilotRepository pilot;
    late QuranAudioController c;
    setUp(() {
      player = ContinuousPlayer()
        ..durationOverride = const Duration(seconds: 34);
      everyAyah = ControlledRepository();
      pilot = PilotRepository();
      c = QuranAudioController.forTesting(
        player: player,
        repository: everyAyah,
        continuousRepository: pilot,
        continuousEnabled: true,
        resolveIntroduction: fixtureIntroduction,
      );
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
      'autoplays one source and never saves EveryAyah in parallel',
      () async {
        await c.playPlan(selection());
        await flush();
        expect(c.playing, isTrue);
        expect(c.audible, isTrue);
        expect(player.starts, 1);
        expect(player.sourceLoads, 1);
        expect(player.queue, hasLength(1));
        expect(
          (player.queue.single as UriAudioSource).uri.path,
          '/mp3quran/067.mp3',
        );
        await c.downloadSelection(selection());
        expect(everyAyah.requested, isEmpty);
        expect(c.offlineDownloading, isFalse);
      },
    );
    test(
      'Bismillah, all 30 ayahs, silence and page-following use real position',
      () async {
        await c.playPlan(selection());
        position(1000);
        expect(c.isIntroduction, isTrue);
        expect(c.currentAyah, isNull);
        expect(c.currentMediaItem!.title, contains('Bismillah'));
        for (var ayah = 1; ayah <= 30; ayah++) {
          position((ayah + 2) * 1000);
          expect(c.currentAyah, ayah);
          expect(c.currentMediaItem!.extras!['ayah'], ayah);
          expect(c.currentIndex, ayah - 1);
        }
        final follower = AudioPageFollower();
        expect(
          follower.targetPage(
            playing: c.playing,
            session: c.playbackSessionId,
            cycle: c.currentRepeat,
            surah: c.currentSurah,
            ayah: c.currentAyah,
            currentPage: 0,
            portrait: true,
            mushaf: 'madani',
          ),
          isNotNull,
        );
        position(32800);
        expect(c.currentItem, isNull);
        expect(c.currentSurah, 67);
        expect(c.currentAyah, isNull);
        expect(c.isIntroduction, isFalse);
        expect(player.sourceLoads, 1);
        expect(player.appends, 0);
      },
    );
    test('Next/Previous seek same source while paused or playing', () async {
      await c.playPlan(selection());
      position(1000);
      await c.seekNext();
      expect(player.at.inMilliseconds, 3000);
      expect(c.currentAyah, 1);
      position(17000);
      await c.pause();
      await c.seekNext();
      expect(c.currentAyah, 16);
      await c.seekPrevious();
      expect(c.currentAyah, 15);
      expect(c.paused, isTrue);
      await c.play();
      expect(c.currentAyah, 15);
      expect(player.sourceLoads, 1);
      expect(player.stops, 1);
    });
    for (final count in <int?>[1, 3, null]) {
      test(
        'full-surah repeats $count seek to zero without source reloads',
        () async {
          await c.playPlan(selection(count: count));
          final cycles = count ?? 12;
          for (var cycle = 1; cycle <= cycles; cycle++) {
            expect(c.currentRepeat, cycle);
            position(32700);
            player.complete();
            await flush();
          }
          expect(player.sourceLoads, 1);
          expect(player.seeks, count == null ? cycles : cycles - 1);
          expect(
            c.phase,
            count == null
                ? QuranPlaybackPhase.playing
                : QuranPlaybackPhase.completed,
          );
          expect(everyAyah.requested, isEmpty);
        },
      );
    }
    test(
      'Journey counts each heard ayah using interval duration, excluding Bismillah',
      () async {
        final heard = <String>[];
        var seconds = 0;
        await c.stop();
        c.dispose();
        player = ContinuousPlayer()
          ..durationOverride = const Duration(seconds: 34);
        c = QuranAudioController.forTesting(
          player: player,
          repository: everyAyah,
          continuousRepository: pilot,
          continuousEnabled: true,
          listeningTracker: ListeningTracker(
            onListen: heard.add,
            onSeconds: (s) => seconds += s,
          ),
        );
        await c.playPlan(selection());
        for (final interval in manifest().intervals) {
          for (var ms = interval.startMs; ms < interval.endMs; ms += 50) {
            position(ms);
          }
        }
        await c.pause();
        expect(heard, [for (var a = 1; a <= 30; a++) '67:$a']);
        expect(seconds, greaterThanOrEqualTo(22));
        await c.play();
        position(32799);
        expect(heard, hasLength(30));
      },
    );
    test('Pause during download survives automatic preparation', () async {
      pilot.gate = Completer<void>();
      final preparing = c.playPlan(selection());
      await flush();
      await c.pause();
      pilot.gate!.complete();
      await preparing;
      expect(player.starts, 0);
      expect(c.paused, isTrue);
      await c.play();
      expect(player.starts, 1);
    });
    test('stop and replacement prevent late autoplay', () async {
      pilot.gate = Completer<void>();
      final old = c.playPlan(selection());
      await flush();
      await c.stop();
      await c.playPlan(selection(surah: 66));
      pilot.gate!.complete();
      await old;
      await flush();
      expect(c.usingContinuousAudio, isFalse);
      expect(c.plan!.surah, 66);
      expect(player.starts, 1);
    });
    test(
      'interruptions and noisy audio retain position until explicit Play',
      () async {
        final handler = QuranAudioHandler(c);
        final noisy = StreamController<void>.broadcast(sync: true);
        final interruptions =
            StreamController<AudioInterruptionEvent>.broadcast(sync: true);
        handler.bindSessionEvents(
          becomingNoisy: noisy.stream,
          interruptions: interruptions.stream,
        );
        await c.playPlan(selection());
        position(17000);
        interruptions.add(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        await flush();
        interruptions.add(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        await flush();
        expect(c.paused, isTrue);
        await handler.play();
        expect(c.currentAyah, 15);
        noisy.add(null);
        await flush();
        expect(c.paused, isTrue);
        expect(player.at.inMilliseconds, 17000);
        expect(player.sourceLoads, 1);
        await handler.dispose();
        await noisy.close();
        await interruptions.close();
      },
    );
    for (final kind in ['download', 'load', 'playback']) {
      test(
        '$kind failure falls back once with same selection and cycle',
        () async {
          if (kind == 'download') pilot.fail = true;
          if (kind == 'load') player.failLoads = 1;
          final p = selection(count: 3);
          await c.playPlan(p);
          if (kind == 'playback') {
            position(17000);
            await c.pause();
            player.fail();
            player.fail();
          }
          await flush();
          expect(c.usingContinuousAudio, isFalse);
          expect(c.plan, same(p));
          expect(c.currentRepeat, 1);
          if (kind == 'playback') {
            expect(c.currentItem!.ayah, 15);
            expect(c.paused, isTrue);
            await c.play();
            expect(c.currentAyah, 15);
          }
          expect(everyAyah.requested, isNotEmpty);
          expect(pilot.calls, 1);
          expect(everyAyah.invalidated, isEmpty);
        },
      );
    }
    test(
      'download failure starts selected surah opening despite stale player position',
      () async {
        player.at = const Duration(seconds: 20);
        pilot.fail = true;
        await c.playPlan(selection());
        await flush();
        expect(c.isIntroduction, isTrue);
        expect(everyAyah.requested.first, 'alafasy/67:bismillah');
      },
    );
    for (final p in [
      selection(surah: 66),
      selection(reciter: quranReciters[1]),
      selection(mode: AudioSourceMode.range),
      selection(mode: AudioSourceMode.playlist),
      selection(repeat: AudioRepeatMode.ayah),
    ]) {
      test(
        'unsupported selection ${p.reciter.id}/${p.surah}/${p.sourceMode}/${p.repeatMode} stays EveryAyah',
        () async {
          await c.playPlan(p);
          await flush();
          expect(c.usingContinuousAudio, isFalse);
          expect(pilot.calls, 0);
          expect(everyAyah.requested, isNotEmpty);
        },
      );
    }
    test(
      'decoder fallback preserves repeat counter after a completed cycle',
      () async {
        await c.playPlan(selection(count: 3));
        player.complete();
        await flush();
        position(17000);
        player.fail();
        await flush();
        expect(c.usingContinuousAudio, isFalse);
        expect(c.currentRepeat, 2);
        expect(c.currentAyah, 15);
      },
    );
    test('seek failure falls back to current EveryAyah ayah', () async {
      await c.playPlan(selection());
      position(17000);
      (player as ContinuousPlayer).failSeek = true;
      await c.seekNext();
      await flush();
      expect(c.usingContinuousAudio, isFalse);
      expect(c.currentAyah, 15);
    });
    test('EOF seek failure falls back to next cycle opening', () async {
      await c.playPlan(selection(count: 3));
      position(32700);
      (player as ContinuousPlayer).failSeek = true;
      player.complete();
      await flush();
      expect(c.usingContinuousAudio, isFalse);
      expect(c.currentRepeat, 2);
      expect(c.isIntroduction, isTrue);
    });
    test('wrong decoded duration automatically falls back', () async {
      player.durationOverride = const Duration(seconds: 50);
      await c.playPlan(selection());
      await flush();
      expect(c.usingContinuousAudio, isFalse);
      expect(everyAyah.requested, isNotEmpty);
    });
    test('missing manifest and disabled flag use EveryAyah', () async {
      for (final enabled in [true, false]) {
        final repo = PilotRepository(available: !enabled);
        final controller = QuranAudioController.forTesting(
          player: FakePlayer(),
          repository: everyAyah,
          continuousRepository: repo,
          continuousEnabled: enabled,
          resolveIntroduction: fixtureIntroduction,
        );
        await controller.playPlan(selection());
        await flush();
        expect(controller.usingContinuousAudio, isFalse);
        expect(repo.calls, 0);
        await controller.stop();
        controller.dispose();
      }
    });
  });
}
