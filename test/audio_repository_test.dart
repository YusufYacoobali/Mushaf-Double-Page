import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/bismillah_sources.dart';
import 'audio_playback_test.dart' show FakePlayer, plan, fixtureIntroduction;

Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      throw TimeoutException('Repository operation did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

class TestTransport implements HttpClientAdapter {
  TestTransport(this.bytes);
  final Uint8List bytes;
  int active = 0, maxActive = 0, calls = 0;
  int status = 200;
  bool html = false;
  final payloads = <String, Uint8List>{};
  final statuses = <String, int>{};
  final transientFailures = <String, int>{};
  final started = <String>[];
  final gates = <String, Completer<void>>{};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    active++;
    if (active > maxActive) maxActive = active;
    final name = options.uri.pathSegments.last;
    started.add(name);
    try {
      final gate = gates[name];
      if (gate != null) {
        await Future.any([
          gate.future,
          if (cancelFuture != null)
            cancelFuture.then(
              (_) => throw DioException.requestCancelled(
                requestOptions: options,
                reason: 'cancelled',
              ),
            ),
        ]);
      }
      final failures = transientFailures[name] ?? 0;
      if (failures > 0) transientFailures[name] = failures - 1;
      return ResponseBody.fromBytes(
        html ? '<html>error</html>'.codeUnits : (payloads[name] ?? bytes),
        failures > 0 ? 503 : (statuses[name] ?? status),
        headers: {
          'content-type': [html ? 'text/html' : 'audio/mpeg'],
        },
      );
    } finally {
      active--;
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  late TestTransport transport;
  late AudioRepository repo;
  final reciter = quranReciters.first;
  const item = QuranAudioItem(surah: 112, ayah: 2);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('quran_audio_repository');
    transport = TestTransport(
      await File('test/fixtures/recording.mp3').readAsBytes(),
    );
    repo = AudioRepository(
      directory: () async => dir,
      dio: Dio()..httpClientAdapter = transport,
    );
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
    'validates MPEG frames; rejects HTML, ID3-only and truncated audio',
    () async {
      expect(AudioRepository.validMp3Bytes(transport.bytes), isTrue);
      expect(
        AudioRepository.validMp3Bytes(
          Uint8List.fromList('<html>error</html>'.codeUnits),
        ),
        isFalse,
      );
      expect(
        AudioRepository.validMp3Bytes(
          Uint8List.fromList([73, 68, 51, ...List.filled(200, 0)]),
        ),
        isFalse,
      );
      expect(
        AudioRepository.validMp3Bytes(
          transport.bytes.sublist(0, transport.bytes.length - 40),
        ),
        isFalse,
      );
    },
  );
  test(
    'corrupt legacy file is replaced atomically; cached audio works offline',
    () async {
      final file = await repo.fileFor(reciter, item);
      await file.parent.create(recursive: true);
      await file.writeAsString('not audio');
      final path = await repo.recording(reciter, item, CancelToken());
      expect(path, endsWith('audio/alafasy/112002.mp3'));
      expect(await AudioRepository.validMp3(File(path)), isTrue);
      transport.status = 404;
      expect(await repo.recording(reciter, item, CancelToken()), path);
      expect(transport.calls, 1);
      expect(
        await dir
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .length,
        0,
      );
    },
  );
  test(
    'HTML and permanent missing recording are classified and never published',
    () async {
      transport.html = true;
      await expectLater(
        repo.recording(reciter, item, CancelToken()),
        throwsA(
          isA<AudioFailure>().having(
            (e) => e.kind,
            'kind',
            AudioFailureKind.corrupt,
          ),
        ),
      );
      expect(await (await repo.fileFor(reciter, item)).exists(), isFalse);
      transport.html = false;
      transport.status = 404;
      await expectLater(
        repo.recording(reciter, item, CancelToken()),
        throwsA(
          isA<AudioFailure>().having(
            (e) => e.kind,
            'kind',
            AudioFailureKind.missing,
          ),
        ),
      );
    },
  );
  test(
    'two downloads maximum; urgent boundary precedes queued prefetch',
    () async {
      final token = CancelToken();
      for (final a in [2, 3]) {
        transport.gates['11200$a.mp3'] = Completer<void>();
      }
      Future<String> get(int ayah, {bool urgent = false}) => repo.recording(
        reciter,
        QuranAudioItem(surah: 112, ayah: ayah),
        token,
        urgent: urgent,
      );
      final first = get(2), second = get(3, urgent: true), future = get(4);
      await waitFor(() => transport.started.length == 2);
      final needed = get(1, urgent: true);
      transport.gates['112002.mp3']!.complete();
      await first;
      await needed;
      expect(
        transport.started.take(2),
        unorderedEquals(['112002.mp3', '112003.mp3']),
      );
      expect(transport.started[2], '112001.mp3');
      transport.gates['112003.mp3']!.complete();
      await second;
      await future;
      expect(transport.maxActive, 2);
    },
  );
  test(
    'cancelled delayed request cleans partial files and does not become cache',
    () async {
      transport.gates['112002.mp3'] = Completer<void>();
      final token = CancelToken();
      final download = repo.recording(reciter, item, token);
      final expectation = expectLater(download, throwsA(isA<DioException>()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      token.cancel('Stop');
      await expectation;
      expect(await (await repo.fileFor(reciter, item)).exists(), isFalse);
      expect(
        await dir
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .length,
        0,
      );
    },
  );
  test('prefetch and urgent access deduplicate the same recording', () async {
    final token = CancelToken();
    final a = repo.recording(reciter, item, token, urgent: false);
    final b = repo.recording(reciter, item, token);
    expect(await a, await b);
    expect(transport.calls, 1);
  });
  test(
    'background requests reserve a slot for playback and cannot starve upcoming ayahs',
    () async {
      transport.gates['112002.mp3'] = Completer<void>();
      final token = CancelToken();
      final background = repo.recording(reciter, item, token, urgent: false);
      await waitFor(() => transport.started.contains('112002.mp3'));
      final later = repo.recording(
        reciter,
        const QuranAudioItem(surah: 112, ayah: 3),
        token,
        urgent: false,
      );
      await waitFor(() => transport.started.length == 1);
      final upcoming = repo.recording(
        reciter,
        const QuranAudioItem(surah: 112, ayah: 4),
        token,
      );
      await upcoming;
      expect(transport.started, ['112002.mp3', '112004.mp3']);
      expect(transport.maxActive, 2);
      transport.gates['112002.mp3']!.complete();
      await background;
      await later;
    },
  );
  test(
    'playback and automatic-saving tokens share physical work; cancelling one consumer preserves the other',
    () async {
      transport.gates['112002.mp3'] = Completer<void>();
      final backgroundToken = CancelToken(), playbackToken = CancelToken();
      final background = repo.recording(
        reciter,
        item,
        backgroundToken,
        urgent: false,
      );
      final cancelled = expectLater(background, throwsA(isA<DioException>()));
      await waitFor(() => transport.started.length == 1);
      final playback = repo.recording(reciter, item, playbackToken);
      await Future<void>.delayed(Duration.zero);
      backgroundToken.cancel();
      await cancelled;
      expect(transport.calls, 1);
      transport.gates['112002.mp3']!.complete();
      final path = await playback;
      expect(await AudioRepository.validMp3(File(path)), isTrue);
      expect(transport.calls, 1);
    },
  );
  test(
    'replacement can re-request a just-cancelled physical recording without stale cancellation',
    () async {
      transport.gates['112002.mp3'] = Completer<void>();
      final old = CancelToken();
      final abandoned = expectLater(
        repo.recording(reciter, item, old),
        throwsA(isA<DioException>()),
      );
      await waitFor(() => transport.started.length == 1);
      old.cancel();
      await abandoned;
      transport.gates.remove('112002.mp3');
      final path = await repo.recording(reciter, item, CancelToken());
      expect(await AudioRepository.validMp3(File(path)), isTrue);
      expect(transport.calls, 2);
      expect(
        await dir
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .length,
        0,
      );
    },
  );
  test(
    'introduction is cached separately without numbered verse identity',
    () async {
      final intro = QuranAudioItem(
        surah: 112,
        source: fixtureIntroduction(reciter, 112).source,
      );
      final path = await repo.recording(reciter, intro, CancelToken());
      expect(path, endsWith('112000.mp3'));
      transport.status = 404;
      expect(await repo.recording(reciter, intro, CancelToken()), path);
      expect(transport.calls, 1);
      expect(intro.ayah, isNull);
    },
  );
  test(
    'a complete cached selection including introduction plays with transport offline',
    () async {
      for (final item in [
        QuranAudioItem(
          surah: 112,
          source: fixtureIntroduction(reciter, 112).source,
        ),
        const QuranAudioItem(surah: 112, ayah: 1),
        const QuranAudioItem(surah: 112, ayah: 2),
      ]) {
        await repo.recording(reciter, item, CancelToken());
      }
      transport.status = 404;
      transport.calls = 0;
      final player = FakePlayer();
      final controller = QuranAudioController.forTesting(
        player: player,
        repository: repo,
        resolveIntroduction: fixtureIntroduction,
      );
      await controller.playPlan(plan(from: 1, to: 2));
      expect(controller.isIntroduction, isTrue);
      await waitFor(() => controller.nativeQueueLength == 3);
      player.advance();
      await waitFor(() => controller.currentAyah == 1);
      expect(controller.currentAyah, 1);
      player.advance();
      await waitFor(() => controller.currentAyah == 2);
      expect(controller.currentAyah, 2);
      player.advance();
      await waitFor(() => controller.phase == QuranPlaybackPhase.completed);
      expect(controller.phase, QuranPlaybackPhase.completed);
      expect(transport.calls, 0);
      await controller.stop();
      controller.dispose();
    },
  );
  test(
    'source resolution is explicit; directory presence is not content verification',
    () {
      for (final reciter in quranReciters) {
        expect(
          BismillahSources.resolve(reciter, 1).kind,
          BismillahPolicyKind.notRequired,
        );
        expect(
          BismillahSources.resolve(reciter, 9).kind,
          BismillahPolicyKind.notRequired,
        );
        for (final surah in [2, 112, 114]) {
          final policy = BismillahSources.resolve(reciter, surah);
          expect(policy.evidence, isNotEmpty);
          if (policy.kind == BismillahPolicyKind.separateVerifiedRecording) {
            expect(policy.source, isNotNull);
            expect(policy.source!.verification, isNotEmpty);
          }
        }
      }
    },
  );

  test(
    'reusable introduction has one physical cache entry across destinations',
    () async {
      final source = AudioRecordingSource(
        id: 'alafasy/001001.mp3',
        url: 'https://example.test/001001.mp3',
        cacheFilename: '001001.mp3',
        sha256: crypto.sha256.convert(transport.bytes).toString(),
        verification: 'Synthetic fixture',
      );
      final a = QuranAudioItem(surah: 2, source: source);
      final b = QuranAudioItem(surah: 112, source: source);
      expect(a.key, isNot(b.key));
      expect(a.recordingId, b.recordingId);
      expect(
        await repo.recording(reciter, a, CancelToken()),
        await repo.recording(reciter, b, CancelToken()),
      );
      expect(transport.calls, 1);
    },
  );

  test(
    'offline selection enforces the audited destination hash before reporting availability',
    () async {
      final controller = QuranAudioController.forTesting(
        player: FakePlayer(),
        repository: repo,
        resolveIntroduction: (_, _) => BismillahResolution(
          BismillahPolicyKind.embeddedInOpeningAyah,
          openingSha256: '0'.padLeft(64, '0'),
          evidence: 'Synthetic changed destination',
        ),
      );
      await controller.downloadSelection(plan(from: 1, to: 1));
      expect(controller.downloadState.completed, 0);
      expect(controller.downloadState.message, contains('incomplete'));
      final file = await repo.fileFor(
        reciter,
        const QuranAudioItem(surah: 112, ayah: 1),
      );
      expect(await file.exists(), isFalse);
      controller.dispose();
    },
  );
  test(
    'valid MPEG bytes with a changed audited hash are rejected before publication',
    () async {
      final source = AudioRecordingSource(
        id: 'audited',
        url: 'https://example.test/intro.mp3',
        cacheFilename: 'intro.mp3',
        sha256: '0'.padLeft(64, '0'),
        verification: 'Synthetic mismatch',
      );
      final item = QuranAudioItem(surah: 112, source: source);
      await expectLater(
        repo.recording(reciter, item, CancelToken()),
        throwsA(
          isA<AudioFailure>().having(
            (e) => e.kind,
            'kind',
            AudioFailureKind.corrupt,
          ),
        ),
      );
      expect(await (await repo.fileFor(reciter, item)).exists(), isFalse);
    },
  );
}
