import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/bismillah_sources.dart';
import 'audio_test_fixtures.dart';
import 'audio_repository_test.dart' show TestTransport, waitFor;
import 'bismillah_policy_test.dart'
    show productionQueues, expectedSequence, occurrenceLabel;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late TestTransport transport;
  late AudioRepository repo;
  late FakePlayer player;
  late QuranAudioController c;
  final reciter = quranReciters.first;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('automatic_quran_audio');
    transport = TestTransport(
      await File('test/fixtures/recording.mp3').readAsBytes(),
    );
    final source = BismillahSources.resolve(reciter, 2).source!;
    transport.payloads[source.cacheFilename] = await File(
      'test/fixtures/bismillah/${reciter.id}.mp3',
    ).readAsBytes();
    repo = AudioRepository(
      directory: () async => dir,
      dio: Dio()..httpClientAdapter = transport,
    );
    player = FakePlayer();
    c = QuranAudioController.forTesting(player: player, repository: repo);
  });
  tearDown(() async {
    await c.stop();
    c.dispose();
    await waitFor(() => transport.active == 0);
    await flush();
    await dir.delete(recursive: true);
  });
  Future<void> saved() =>
      waitFor(() => c.downloadState.message == 'Selection available offline');
  Future<List<FileSystemEntity>> parts() =>
      dir.list(recursive: true).where((f) => f.path.endsWith('.part')).toList();

  for (final queue in productionQueues) {
    for (final mode in AudioRepeatMode.values) {
      test(
        'Play automatically caches whole production queue $queue ${mode.name}, including one shared Bismillah',
        () async {
          final selection = plan(queue: queue, count: 2, repeat: mode);
          await c.playPlan(selection);
          await saved();
          final expectedFiles = <String>{
            for (final v in selection.uniqueVerses())
              '${AudioRepository.audioId(v.surah, v.ayah)}.mp3',
            BismillahSources.resolve(reciter, 2).source!.cacheFilename,
          };
          expect(transport.started.toSet(), expectedFiles);
          expect(
            transport.calls,
            expectedFiles.length,
          ); // No duplicate in-flight or repeat downloads.
          expect(transport.maxActive, lessThanOrEqualTo(2));
          expect(c.downloadState.completed, expectedFiles.length);
          expect(c.downloadState.total, expectedFiles.length);
          expect(player.sourceLoads, 1);
          expect(c.playing, isTrue);
          expect(await parts(), isEmpty);
          final intro = QuranAudioItem(surah: 3);
          expect(await (await repo.fileFor(reciter, intro)).exists(), isTrue);
          // A fresh controller has no in-memory recording state to disguise a miss.
          await c.stop();
          c.dispose();
          transport.status = 404;
          final calls = transport.calls;
          player = FakePlayer();
          c = QuranAudioController.forTesting(player: player, repository: repo);
          await c.playPlan(selection);
          await saved();
          expect(transport.calls, calls);
          expect(
            c.currentItem!.key,
            queue.first == 1 ? '1:1' : '${queue.first}:bismillah',
          );
          if (queue.first == 112) {
            for (final expected in expectedSequence(selection)) {
              expect(occurrenceLabel(c.currentOccurrence!), expected);
              player.advance();
              // Real filesystem I/O must settle before the next simulated clip ends.
              await waitFor(
                () =>
                    c.phase == QuranPlaybackPhase.completed ||
                    (c.currentOccurrence != null &&
                        occurrenceLabel(c.currentOccurrence!) != expected &&
                        c.nativeQueueLength >= 1),
              );
              await flush();
            }
            expect(c.phase, QuranPlaybackPhase.completed);
            expect(transport.calls, calls);
          }
        },
      );
    }
  }
  test(
    'all 22 production reciters automatically cache and replay their own canonical source offline',
    () async {
      for (final selected in quranReciters) {
        final source = BismillahSources.resolve(selected, 112).source!;
        transport.payloads.clear();
        transport.payloads[source.cacheFilename] = await File(
          'test/fixtures/bismillah/${selected.id}.mp3',
        ).readAsBytes();
        await c.playPlan(plan(reciter: selected, from: 1, to: 2));
        await saved();
        expect(c.plan!.reciter.id, selected.id);
        expect(c.currentOccurrence!.recordingId, source.id);
        expect(
          await (await repo.fileFor(
            selected,
            const QuranAudioItem(surah: 113),
          )).exists(),
          isTrue,
        );
      }
      final calls = transport.calls;
      transport.status = 404;
      for (final selected in quranReciters) {
        await c.playPlan(plan(reciter: selected, from: 1, to: 2));
        await saved();
        expect(
          c.currentOccurrence!.recordingId,
          BismillahSources.resolve(selected, 112).source!.id,
        );
      }
      expect(transport.calls, calls);
    },
  );
  test(
    'full-surah mode caches every ayah even when edited range is narrower',
    () async {
      await c.playPlan(
        AudioPlaybackPlan(
          reciter: reciter,
          surah: 112,
          fromAyah: 2,
          toAyah: 2,
          repeatCount: 3,
          repeatMode: AudioRepeatMode.range,
          sourceMode: AudioSourceMode.surah,
        ),
      );
      await saved();
      expect(transport.started.toSet(), {
        '001001.mp3',
        '112001.mp3',
        '112002.mp3',
        '112003.mp3',
        '112004.mp3',
      });
      expect(transport.calls, 5);
      expect(c.currentItem!.key, '112:bismillah');
    },
  );
  test(
    'first recording starts while a distant background download is blocked; upcoming ayahs have capacity',
    () async {
      final gate = transport.gates['002006.mp3'] = Completer<void>();
      final progress = <int>[];
      c.addListener(() {
        if (c.offlineDownloading) progress.add(c.downloadState.completed);
      });
      await c.playPlan(plan(surah: 2, from: 2, to: 10, count: null));
      await waitFor(() => transport.started.contains('002006.mp3'));
      expect(c.currentAyah, 2);
      expect(c.playing, isTrue);
      expect(c.offlineDownloading, isTrue);
      player.advance();
      await waitFor(() => c.currentAyah == 3);
      await flush();
      player.advance();
      await waitFor(
        () => c.currentAyah == 4 && transport.started.contains('002007.mp3'),
      );
      // 6 is still blocked; 7 can use the slot reserved for upcoming playback.
      expect(c.currentAyah, 4);
      expect(transport.maxActive, 2);
      await c.seekNext();
      expect(c.currentAyah, 5);
      expect(c.offlineDownloading, isTrue);
      await c.seekPrevious();
      expect(c.currentAyah, 4);
      expect(c.offlineDownloading, isTrue);
      await c.pause();
      gate.complete();
      await saved();
      expect(progress.any((n) => n > 0 && n < 9), isTrue);
      expect(c.playing, isFalse);
      expect(transport.calls, 9);
      expect(c.downloadState.completed, 9);
    },
  );
  test(
    'failed canonical Bismillah is handled internally and ayah 1 is never lost or duplicated',
    () async {
      final source = BismillahSources.resolve(reciter, 112).source!;
      transport.statuses[source.cacheFilename] = 404;
      await c.playPlan(plan(from: 1, to: 2, count: 2));
      await waitFor(() => !c.offlineDownloading);
      expect(c.currentAyah, 1);
      expect(c.error, isNull);
      expect(c.introductionNotice, contains('Bismillah is unavailable'));
      expect(c.downloadState.message, contains('incomplete'));
      expect(c.downloadState.completed, 2);
      expect(
        transport.started.where((n) => n == source.cacheFilename).length,
        1,
      );
      final heard = <String>[];
      for (var i = 0; i < 4; i++) {
        heard.add(c.currentItem!.key);
        player.advance();
        await flush();
      }
      expect(heard, ['112:1', '112:2', '112:1', '112:2']);
      expect(c.phase, QuranPlaybackPhase.completed);
      expect(player.played.where((o) => o.item.isIntroduction), isEmpty);
      expect(await parts(), isEmpty);
    },
  );
  test(
    'background retries and permanent failures do not stop saving later recordings',
    () async {
      transport.transientFailures['002006.mp3'] = 2;
      transport.statuses['002007.mp3'] = 404;
      await c.playPlan(plan(surah: 2, from: 2, to: 8));
      await waitFor(() => !c.offlineDownloading);
      expect(c.currentAyah, 2);
      expect(c.error, isNull);
      expect(c.downloadState.message, contains('incomplete'));
      expect(c.downloadState.completed, 6);
      expect(transport.started.where((n) => n == '002006.mp3').length, 3);
      expect(
        await (await repo.fileFor(
          reciter,
          const QuranAudioItem(surah: 2, ayah: 8),
        )).exists(),
        isTrue,
      );
      expect(await parts(), isEmpty);
    },
  );
  test(
    'changed canonical Bismillah bytes are rejected, retried finitely, and never announced as played or saved',
    () async {
      final source = BismillahSources.resolve(reciter, 112).source!;
      transport.payloads[source.cacheFilename] = transport.bytes;
      await c.playPlan(plan(from: 1, to: 2));
      await waitFor(() => !c.offlineDownloading);
      expect(c.currentAyah, 1);
      expect(c.error, isNull);
      expect(c.downloadState.message, contains('incomplete'));
      expect(
        transport.started.where((n) => n == source.cacheFilename).length,
        4,
      );
      expect(
        await (await repo.fileFor(
          reciter,
          const QuranAudioItem(surah: 112),
        )).exists(),
        isFalse,
      );
      expect(player.played.where((o) => o.item.isIntroduction), isEmpty);
      expect(await parts(), isEmpty);
    },
  );
  test(
    'decoder failures invalidate offline availability and automatically continue with numbered ayah 1',
    () async {
      await c.playPlan(plan(from: 1, to: 2, count: 2));
      await saved();
      for (var i = 0; i < 4; i++) {
        player.fail();
        await flush();
        await waitFor(() => c.phase == QuranPlaybackPhase.playing && c.audible);
      }
      await waitFor(() => !c.offlineDownloading);
      expect(c.currentAyah, 1);
      expect(c.error, isNull);
      expect(c.introductionNotice, contains('unavailable'));
      expect(c.downloadState.message, contains('incomplete'));
      final heard = <String>[];
      for (var i = 0; i < 4; i++) {
        heard.add(c.currentItem!.key);
        player.advance();
        await flush();
      }
      expect(heard, ['112:1', '112:2', '112:1', '112:2']);
    },
  );
  test(
    'cancelling offline saving leaves playback and completed cache intact; replacement cancels stale work',
    () async {
      transport.gates['002008.mp3'] = Completer<void>();
      await c.playPlan(plan(surah: 2, from: 2, to: 10));
      await waitFor(() => transport.started.contains('002008.mp3'));
      c.cancelDownload();
      await waitFor(() => transport.active == 0);
      await flush();
      expect(c.playing, isTrue);
      expect(c.currentAyah, 2);
      expect(c.downloadState.message, isEmpty);
      expect(
        await (await repo.fileFor(
          reciter,
          const QuranAudioItem(surah: 2, ayah: 2),
        )).exists(),
        isTrue,
      );
      expect(
        await (await repo.fileFor(
          reciter,
          const QuranAudioItem(surah: 2, ayah: 8),
        )).exists(),
        isFalse,
      );
      expect(await parts(), isEmpty);
      // Replacement starts from cached 2, cancels a newly blocked distant request.
      transport.gates['002009.mp3'] = Completer<void>();
      await c.playPlan(plan(surah: 2, from: 2, to: 10));
      await waitFor(
        () => transport.started.where((n) => n == '002008.mp3').length == 2,
      );
      await c.playPlan(plan(surah: 113, from: 2, to: 3));
      await saved();
      expect(c.currentSurah, 113);
      expect(c.currentAyah, 2);
      expect(c.downloadState.total, 2);
      expect(await parts(), isEmpty);
    },
  );
  test(
    'lock-screen Stop cancels automatic saving and retains completed recordings',
    () async {
      transport.gates['002008.mp3'] = Completer<void>();
      await c.playPlan(plan(surah: 2, from: 2, to: 10));
      await waitFor(() => transport.started.contains('002008.mp3'));
      final handler = QuranAudioHandler(c);
      await handler.pause();
      expect(c.offlineDownloading, isTrue);
      await handler.play();
      expect(c.currentAyah, 2);
      await handler.stop();
      await waitFor(() => transport.active == 0);
      await flush();
      expect(c.phase, QuranPlaybackPhase.idle);
      expect(c.offlineDownloading, isFalse);
      expect(await parts(), isEmpty);
      expect(
        await (await repo.fileFor(
          reciter,
          const QuranAudioItem(surah: 2, ayah: 2),
        )).exists(),
        isTrue,
      );
    },
  );
}
