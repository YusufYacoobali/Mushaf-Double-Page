import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/bismillah_sources.dart';
import 'audio_repository_test.dart' show TestTransport, waitFor;
import 'audio_test_fixtures.dart';

const sampleReciters = ['alafasy', 'husary', 'shaatree', 'minshawy_mujawwad'];

class _CountingCancelToken extends CancelToken {
  int watches = 0;
  @override
  Future<DioException> get whenCancel {
    watches++;
    return super.whenCancel;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late TestTransport transport;
  late AudioRepository repo;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gapless_preparation');
    transport = TestTransport(
      await File('test/fixtures/recording.mp3').readAsBytes(),
    );
    repo = AudioRepository(
      directory: () async => dir,
      dio: Dio()..httpClientAdapter = transport,
    );
  });
  tearDown(() async {
    await waitFor(() => transport.active == 0);
    await flush();
    await dir.delete(recursive: true);
  });
  Future<void> cache(
    Reciter reciter,
    QuranAudioItem item,
    String fixture,
  ) async {
    final file = await repo.fileFor(reciter, item);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await File(fixture).readAsBytes());
  }

  Future<void> cacheSamples(Reciter reciter) async {
    await cache(
      reciter,
      const QuranAudioItem(surah: 112),
      'test/fixtures/bismillah/${reciter.id}.mp3',
    );
    for (final surah in [112, 113]) {
      for (var ayah = 1; ayah <= (surah == 112 ? 4 : 2); ayah++) {
        await cache(
          reciter,
          QuranAudioItem(surah: surah, ayah: ayah),
          'test/fixtures/gapless/${reciter.id}-${AudioRepository.audioId(surah, ayah)}.mp3',
        );
      }
    }
  }

  Future<void> fillNative(
    QuranAudioController c,
    FakePlayer player,
    bool hasNext,
  ) async {
    await waitFor(
      () =>
          c.phase == QuranPlaybackPhase.completed ||
          player.queue.length - player.index >= (hasNext ? 2 : 1),
    );
    await flush();
  }

  for (final rid in sampleReciters) {
    final reciter = quranReciters.firstWhere((r) => r.id == rid);
    test(
      'cached native lookahead is ready while both network workers remain blocked: $rid',
      () async {
        await cacheSamples(reciter);
        final load = Completer<void>();
        final player = FakePlayer()..loadGate = load;
        final c = QuranAudioController.forTesting(
          player: player,
          repository: repo,
        );
        final playing = c.playPlan(plan(reciter: reciter, from: 1, to: 4));
        await waitFor(() => player.sourceLoads == 1);
        final token = CancelToken();
        transport.gates['002008.mp3'] = Completer<void>();
        transport.gates['002009.mp3'] = Completer<void>();
        final downloads = [
          repo.recording(
            reciter,
            const QuranAudioItem(surah: 2, ayah: 8),
            token,
            urgent: false,
          ),
          repo.recording(
            reciter,
            const QuranAudioItem(surah: 2, ayah: 9),
            token,
          ),
        ];
        final settled = Future.wait(
          downloads.map((f) => f.then<void>((_) {}, onError: (Object _) {})),
        );
        try {
          await waitFor(() => transport.active == 2);
          load.complete();
          await playing;
          await waitFor(() => player.queue.length >= 4);
          final pauses = player.pauses, stops = player.stops;
          final expected = [
            '112:bismillah',
            '112:1',
            '112:2',
            '112:3',
            '112:4',
          ];
          for (var i = 0; i < expected.length; i++) {
            await fillNative(c, player, i + 1 < expected.length);
            expect(c.currentItem!.key, expected[i]);
            expect(player.sourceLoads, 1);
            expect(player.pauses, pauses);
            expect(player.stops, stops);
            expect(player.seeks, 0);
            expect(transport.active, 2);
            player.advance();
            await flush();
          }
          expect(c.phase, QuranPlaybackPhase.completed);
          expect(transport.calls, 2);
        } finally {
          token.cancel();
          await settled;
          await c.stop();
          c.dispose();
        }
      },
    );
    for (final stop in [false, true]) {
      test(
        'transition ${stop ? "Stop" : "Pause/Resume"} cannot resurrect or skip cached audio: $rid',
        () async {
          await cacheSamples(reciter);
          final gate = Completer<void>();
          final player = FakePlayer()..appendGate = gate;
          final c = QuranAudioController.forTesting(
            player: player,
            repository: repo,
          );
          await c.playPlan(plan(reciter: reciter, from: 2, to: 4));
          await waitFor(() => player.appendAttempts > 0);
          player.advance();
          await flush();
          expect(c.phase, QuranPlaybackPhase.buffering);
          if (stop) {
            await c.stop();
            gate.complete();
            await flush();
            expect(c.currentItem, isNull);
            expect(c.phase, QuranPlaybackPhase.idle);
            expect(player.active, isFalse);
          } else {
            await c.pause();
            gate.complete();
            await waitFor(
              () =>
                  c.phase == QuranPlaybackPhase.paused &&
                  c.currentItem?.ayah == 3,
            );
            expect(c.playing, isFalse);
            await c.play();
            expect(c.currentAyah, 3);
          }
          await c.stop();
          c.dispose();
        },
      );
    }
    test(
      'verified cached introduction bypasses occupied download workers: $rid',
      () async {
        const intro = QuranAudioItem(surah: 113);
        await cache(reciter, intro, 'test/fixtures/bismillah/$rid.mp3');
        final token = CancelToken();
        transport.gates['002008.mp3'] = Completer<void>();
        transport.gates['002009.mp3'] = Completer<void>();
        final downloads = [
          repo.recording(
            reciter,
            const QuranAudioItem(surah: 2, ayah: 8),
            token,
            urgent: false,
          ),
          repo.recording(
            reciter,
            const QuranAudioItem(surah: 2, ayah: 9),
            token,
          ),
        ];
        final settled = Future.wait(
          downloads.map((f) => f.then<void>((_) {}, onError: (Object _) {})),
        );
        try {
          await waitFor(() => transport.active == 2);
          final result = await repo
              .recording(reciter, intro, CancelToken())
              .timeout(const Duration(milliseconds: 500));
          expect(
            await File(result).readAsBytes(),
            await File('test/fixtures/bismillah/$rid.mp3').readAsBytes(),
          );
          expect(transport.active, 2);
          expect(transport.calls, 2);
        } finally {
          token.cancel();
          await settled;
        }
      },
    );
    for (final mode in AudioRepeatMode.values) {
      test(
        'actual cached sources retain native ayah/Bismillah transitions without reload or editing: $rid ${mode.name}',
        () async {
          await cacheSamples(reciter);
          transport.status = 404; // Offline; no recording should use transport.
          final player = FakePlayer();
          final c = QuranAudioController.forTesting(
            player: player,
            repository: repo,
          );
          final handler = QuranAudioHandler(c);
          final selection = AudioPlaybackPlan(
            reciter: reciter,
            surah: 112,
            fromAyah: 1,
            toAyah: 4,
            repeatCount: 2,
            repeatMode: mode,
            sourceMode: AudioSourceMode.playlist,
            surahQueue: const [112, 113],
          );
          // Complete the actual second surah for the queue case.
          for (var ayah = 3; ayah <= 5; ayah++) {
            await cache(
              reciter,
              QuranAudioItem(surah: 113, ayah: ayah),
              'test/fixtures/gapless/$rid-${AudioRepository.audioId(113, ayah)}.mp3',
            );
          }
          final before = <String, String>{};
          await for (final file in dir.list(recursive: true)) {
            if (file is File) {
              before[file.path] = crypto.sha256
                  .convert(await file.readAsBytes())
                  .toString();
            }
          }
          await c.playPlan(selection);
          await flush();
          final pauses = player.pauses,
              stops = player.stops,
              seeks = player.seeks;
          final heard = <String>[];
          final expected = <String>[];
          for (
            var cycle = 0;
            cycle < (mode == AudioRepeatMode.range ? 2 : 1);
            cycle++
          ) {
            for (final surah in [112, 113]) {
              expected.add('$surah:bismillah');
              for (var ayah = 1; ayah <= (surah == 112 ? 4 : 5); ayah++) {
                for (
                  var repeat = 0;
                  repeat < (mode == AudioRepeatMode.ayah ? 2 : 1);
                  repeat++
                ) {
                  expected.add('$surah:$ayah');
                }
              }
            }
          }
          for (final item in expected) {
            await fillNative(c, player, heard.length + 1 < expected.length);
            expect(c.currentItem!.key, item);
            heard.add(item);
            expect(
              handler.mediaItem.value!.extras!['introduction'],
              c.isIntroduction,
            );
            expect(
              c.currentAyah,
              c.isIntroduction ? isNull : c.currentItem!.ayah,
            );
            expect(player.sourceLoads, 1);
            expect(player.pauses, pauses);
            expect(player.stops, stops);
            expect(player.seeks, seeks);
            expect(c.nativeQueueLength, lessThanOrEqualTo(6));
            expect(c.retainedSourceCount, lessThanOrEqualTo(6));
            for (final source in player.queue) {
              expect(
                source,
                isA<UriAudioSource>(),
              ); // No clipping, overlap or derived audio.
              expect((source as UriAudioSource).uri.scheme, 'file');
            }
            player.advance();
            await flush();
          }
          expect(heard, expected);
          expect(c.phase, QuranPlaybackPhase.completed);
          expect(transport.calls, 0);
          for (final entry in before.entries) {
            expect(
              crypto.sha256
                  .convert(await File(entry.key).readAsBytes())
                  .toString(),
              entry.value,
            );
          }
          await c.stop();
          c.dispose();
        },
      );
    }
  }
  test(
    'long recording and pause/resume retain source, position and complete original bytes',
    () async {
      final reciter = quranReciters.firstWhere(
        (r) => r.id == 'minshawy_mujawwad',
      );
      await cache(
        reciter,
        const QuranAudioItem(surah: 1, ayah: 7),
        'test/fixtures/gapless/minshawy_mujawwad-001007.mp3',
      );
      final measurements =
          jsonDecode(File('docs/audio-gap-analysis.json').readAsStringSync())
              as Map<String, dynamic>;
      final longClip = (measurements['recordings'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((r) => r['id'] == 'minshawy_mujawwad/001007.mp3');
      final player = FakePlayer()
        ..durationOverride = Duration(
          milliseconds: (longClip['pcmDurationMs'] as num).round(),
        );
      final c = QuranAudioController.forTesting(
        player: player,
        repository: repo,
      );
      final p = plan(reciter: reciter, surah: 1, from: 7, to: 7, count: null);
      await c.playPlan(p);
      await flush();
      for (var i = 0; i < 25; i++) {
        await fillNative(c, player, true);
        final occurrence = c.currentOccurrence!.occurrenceId;
        await c.seek(const Duration(seconds: 12));
        await c.pause();
        await c.play();
        expect(c.currentOccurrence!.occurrenceId, occurrence);
        expect(c.playbackPosition, const Duration(seconds: 12));
        player.advance();
        await flush();
        expect(c.currentAyah, 7);
        expect(c.nativeQueueLength, lessThanOrEqualTo(6));
      }
      expect(player.sourceLoads, 1);
      expect(transport.calls, 0);
      await c.stop();
      c.dispose();
    },
  );
  test(
    'long repeat sessions share one cancellation watcher across completed cache reads',
    () async {
      final reciter = quranReciters.first;
      const item = QuranAudioItem(surah: 112, ayah: 2);
      await cache(reciter, item, 'test/fixtures/gapless/alafasy-112002.mp3');
      final token = _CountingCancelToken();
      for (var i = 0; i < 300; i++) {
        await repo.recording(reciter, item, token);
      }
      expect(token.watches, 1);
      expect(transport.calls, 0);
      token.cancel();
      await flush();
      expect(await (await repo.fileFor(reciter, item)).exists(), isTrue);
    },
  );
  test(
    'a valid MP3 with the wrong cached Bismillah hash cannot bypass audited acquisition',
    () async {
      final reciter = quranReciters.first;
      const intro = QuranAudioItem(surah: 113);
      await cache(reciter, intro, 'test/fixtures/recording.mp3');
      final source = BismillahSources.resolve(reciter, 113).source!;
      transport.payloads[source.cacheFilename] = await File(
        'test/fixtures/bismillah/alafasy.mp3',
      ).readAsBytes();
      final path = await repo.recording(reciter, intro, CancelToken());
      expect(
        crypto.sha256.convert(await File(path).readAsBytes()).toString(),
        source.sha256,
      );
      expect(transport.calls, 1);
      expect(await repo.recording(reciter, intro, CancelToken()), path);
      expect(transport.calls, 1);
    },
  );
}
