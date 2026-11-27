import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/components/audio_modal.dart';
import 'package:mushaf_two_page/components/reader_audio_controls.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/bismillah_sources.dart';
import 'audio_repository_test.dart' show TestTransport, waitFor;
import 'audio_test_fixtures.dart';
import 'bismillah_policy_test.dart' show expectedSequence, occurrenceLabel;

/// A prepared native source can report ready/false while Play is asynchronous.
class DeferredStartPlayer extends FakePlayer {
  final startGate = Completer<void>();
  Completer<void>? stopGate;
  int playRequests = 0, command = 0;
  @override
  Future<void> play() async {
    playRequests++;
    final ticket = command;
    if (!startGate.isCompleted) {
      emitReady(false);
      await startGate.future;
    }
    if (ticket == command) {
      await super.play();
    }
  }

  void emitReady(bool value) {
    active = value;
    state = ProcessingState.ready;
    states.add(PlayerState(value, state));
  }

  @override
  Future<void> pause() {
    command++;
    return super.pause();
  }

  @override
  Future<void> stop() async {
    command++;
    await stopGate?.future;
    await super.stop();
  }
}

class EarlyReturnPlayer extends FakePlayer {
  EarlyReturnPlayer(this.remaining);
  int remaining, requests = 0;
  @override
  Future<void> play() async {
    requests++;
    if (remaining-- > 0) {
      active = false;
      state = ProcessingState.ready;
      states.add(PlayerState(false, state));
      return;
    }
    await super.play();
  }
}

class ProgressRepository extends ControlledRepository {
  final progress = <String, void Function(double)>{};
  @override
  Future<String> recording(
    Reciter reciter,
    QuranAudioItem item,
    CancelToken token, {
    bool urgent = true,
    void Function(double)? onProgress,
  }) {
    if (onProgress != null) {
      progress[item.key] = onProgress;
    }
    return super.recording(
      reciter,
      item,
      token,
      urgent: urgent,
      onProgress: onProgress,
    );
  }
}

void main() {
  test('recitations use neutral media playback and retain pause-on-duck', () {
    const config = QuranAudioHandler.playbackSession;
    expect(config.androidAudioAttributes?.usage, AndroidAudioUsage.media);
    expect(
      config.androidAudioAttributes?.contentType,
      AndroidAudioContentType.unknown,
    );
    expect(config.androidAudioFocusGainType, AndroidAudioFocusGainType.gain);
    expect(config.androidWillPauseWhenDucked, isTrue);
    expect(config.avAudioSessionCategory, AVAudioSessionCategory.playback);
    expect(config.avAudioSessionMode, AVAudioSessionMode.defaultMode);
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Play/Pause/Resume while initial native Stop is pending cannot play an unprepared source',
    () async {
      final stopping = Completer<void>();
      final player = DeferredStartPlayer()..stopGate = stopping;
      final c = QuranAudioController.forTesting(
        player: player,
        repository: ControlledRepository(),
      );
      final starting = c.playPlan(plan());
      await flush();
      await c.play();
      await c.play();
      expect(player.playRequests, 0);
      expect(c.preparing, isTrue);
      await c.pause();
      expect(c.paused, isTrue);
      await c.play();
      expect(c.preparing, isTrue);
      expect(player.playRequests, 0);
      stopping.complete();
      await starting;
      expect(player.playRequests, 1);
      expect(c.paused, isFalse);
      player.startGate.complete();
      await flush();
      expect(c.audible, isTrue);
      expect(player.starts, 1);
      expect(player.sourceLoads, 1);
      await c.stop();
      c.dispose();
    },
  );
  for (final permanent in [false, true]) {
    test(
      'native Play returning ready/false recovers automatically with bounded retries permanent=$permanent',
      () async {
        final player = EarlyReturnPlayer(permanent ? 100 : 1);
        final c = QuranAudioController.forTesting(
          player: player,
          repository: ControlledRepository(),
        );
        await c.playPlan(
          permanent ? plan(from: 2, to: 3) : plan(from: 1, to: 2),
        );
        await flush();
        if (permanent) {
          expect(c.phase, QuranPlaybackPhase.failed);
          expect(player.requests, 4);
          expect(player.starts, 0);
          expect(c.paused, isFalse);
          expect(c.error, isNotNull);
        } else {
          expect(c.audible, isTrue);
          expect(player.requests, 2);
          expect(player.starts, 1);
          expect(c.currentItem!.key, '112:bismillah');
          player.advance();
          await flush();
          expect(c.currentAyah, 1);
          expect(c.error, isNull);
        }
        await c.stop();
        c.dispose();
      },
    );
  }
  for (final queue in [false, true]) {
    test(
      'one Play survives a slow initial ${queue ? "Surah Queue Bismillah" : "ayah"} and delayed ready/false',
      () async {
        final player = DeferredStartPlayer(), repo = ProgressRepository();
        final c = QuranAudioController.forTesting(
          player: player,
          repository: repo,
        );
        final selection = queue
            ? plan(queue: [112, 113, 114], count: 2)
            : plan(from: 2, to: 4);
        final first = queue ? '112:bismillah' : '112:2';
        repo.remainingFailures[first] = 1;
        var recovered = false;
        c.addListener(() {
          if (c.phase == QuranPlaybackPhase.recovering) {
            recovered = true;
            expect(c.preparing, isTrue);
            expect(c.paused, isFalse);
          }
        });
        final initial = repo.gates[first] = Completer<void>();
        final background = repo.gates[queue ? '113:2' : '112:4'] =
            Completer<void>();
        final starting = c.playPlan(selection);
        await flush();
        expect(c.preparing, isTrue);
        expect(c.paused, isFalse);
        expect(player.starts, 0);
        repo.progress[first]!(.3);
        expect(c.statusLabel, 'Downloading');
        initial.complete();
        await starting;
        await flush();
        expect(player.playRequests, 1);
        expect(player.starts, 0);
        expect(c.preparing, isTrue);
        expect(c.playing, isTrue);
        expect(c.paused, isFalse);
        expect(c.audible, isFalse);
        player.emitReady(false);
        await flush();
        expect(c.paused, isFalse);
        player.startGate.complete();
        await flush();
        expect(player.starts, 1);
        expect(recovered, isTrue);
        expect(c.phase, QuranPlaybackPhase.playing);
        expect(c.audible, isTrue);
        if (queue) {
          expect(
            c.currentOccurrence!.recordingId,
            BismillahSources.resolve(selection.reciter, 112).source!.id,
          );
          expect(c.currentAyah, isNull);
        } else {
          expect(c.currentAyah, 2);
        }
        final pauses = player.pauses, loads = player.sourceLoads;
        expect(c.offlineDownloading, isTrue);
        background.complete();
        await flush();
        expect(c.phase, QuranPlaybackPhase.playing);
        expect(player.pauses, pauses);
        expect(player.sourceLoads, loads);
        final expected = queue
            ? expectedSequence(selection)
            : ['112:2/1/1', '112:3/1/1', '112:4/1/1'];
        for (final item in expected) {
          expect(occurrenceLabel(c.currentOccurrence!), item);
          player.emitReady(false);
          await flush();
          expect(c.playing, isTrue);
          expect(c.paused, isFalse);
          player.emitReady(true);
          await flush();
          player.advance();
          await flush();
        }
        expect(c.phase, QuranPlaybackPhase.completed);
        expect(player.playRequests, 1);
        expect(player.sourceLoads, 1);
        await c.stop();
        c.dispose();
      },
    );
  }
  test(
    'cached offline playback auto-starts once despite delayed native readiness',
    () async {
      final dir = await Directory.systemTemp.createTemp('play_intent_cache');
      final transport = TestTransport(
        await File('test/fixtures/recording.mp3').readAsBytes(),
      );
      final repo = AudioRepository(
        directory: () async => dir,
        dio: Dio()..httpClientAdapter = transport,
      );
      final reciter = quranReciters.first;
      for (final ayah in [2, 3]) {
        await repo.recording(
          reciter,
          QuranAudioItem(surah: 112, ayah: ayah),
          CancelToken(),
        );
      }
      transport.calls = 0;
      transport.status = 404;
      final player = DeferredStartPlayer();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: repo,
      );
      await c.playPlan(plan(from: 2, to: 3));
      await flush();
      expect(c.preparing, isTrue);
      expect(c.paused, isFalse);
      player.startGate.complete();
      await waitFor(() => c.audible);
      await waitFor(
        () => c.downloadState.message == 'Selection available offline',
      );
      expect(player.starts, 1);
      expect(c.currentAyah, 2);
      expect(transport.calls, 0);
      await c.stop();
      c.dispose();
      await flush();
      await dir.delete(recursive: true);
    },
  );
  for (final duringDownload in [true, false]) {
    for (final action in ['Pause', 'interruption', 'headset disconnect']) {
      test(
        '$action during ${duringDownload ? "download" : "native startup"} remains paused until explicit Play',
        () async {
          final player = DeferredStartPlayer(), repo = ControlledRepository();
          final c = QuranAudioController.forTesting(
            player: player,
            repository: repo,
          );
          final handler = QuranAudioHandler(c);
          final noisy = StreamController<void>.broadcast(sync: true);
          final interruptions =
              StreamController<AudioInterruptionEvent>.broadcast(sync: true);
          handler.bindSessionEvents(
            becomingNoisy: noisy.stream,
            interruptions: interruptions.stream,
          );
          final gate = repo.gates['112:2'] = Completer<void>();
          final starting = c.playPlan(plan(from: 2, to: 3));
          await flush();
          if (!duringDownload) {
            gate.complete();
            await starting;
            await flush();
          }
          if (action == 'Pause') {
            await handler.pause();
          } else if (action == 'interruption') {
            interruptions.add(
              AudioInterruptionEvent(true, AudioInterruptionType.pause),
            );
          } else {
            noisy.add(null);
          }
          await flush();
          expect(c.paused, isTrue);
          expect(c.playing, isFalse);
          if (!gate.isCompleted) {
            gate.complete();
          }
          player.startGate.complete();
          await starting;
          await flush();
          interruptions.add(
            AudioInterruptionEvent(false, AudioInterruptionType.pause),
          );
          player.emitReady(false);
          await flush();
          expect(c.phase, QuranPlaybackPhase.paused);
          expect(player.starts, 0);
          expect(c.paused, isTrue);
          // Even a late positive native state cannot undo an explicit pause.
          player.emitReady(true);
          await flush();
          expect(player.active, isFalse);
          expect(c.paused, isTrue);
          final id = c.currentOccurrence!.occurrenceId,
              loads = player.sourceLoads;
          await handler.play();
          await flush();
          expect(c.phase, QuranPlaybackPhase.playing);
          expect(player.starts, 1);
          expect(c.currentOccurrence!.occurrenceId, id);
          expect(player.sourceLoads, loads);
          await c.stop();
          await handler.dispose();
          c.dispose();
          await noisy.close();
          await interruptions.close();
        },
      );
    }
  }
  for (final event in [
    'pause interruption',
    'duck interruption',
    'headset disconnect',
  ]) {
    test(
      '$event pauses active recitation without resetting position or resuming on end',
      () async {
        final player = DeferredStartPlayer()..startGate.complete();
        final c = QuranAudioController.forTesting(
          player: player,
          repository: ControlledRepository(),
        );
        final handler = QuranAudioHandler(c);
        final noisy = StreamController<void>.broadcast(sync: true);
        final interruptions =
            StreamController<AudioInterruptionEvent>.broadcast(sync: true);
        handler.bindSessionEvents(
          becomingNoisy: noisy.stream,
          interruptions: interruptions.stream,
        );
        await c.playPlan(plan());
        await flush();
        final id = c.currentOccurrence!.occurrenceId;
        player.at = const Duration(seconds: 3);
        if (event == 'headset disconnect') {
          noisy.add(null);
        } else {
          interruptions.add(
            AudioInterruptionEvent(
              true,
              event == 'duck interruption'
                  ? AudioInterruptionType.duck
                  : AudioInterruptionType.pause,
            ),
          );
        }
        await flush();
        expect(c.paused, isTrue);
        expect(player.active, isFalse);
        interruptions.add(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        player.emitReady(false);
        await flush();
        expect(player.starts, 1);
        expect(c.paused, isTrue);
        expect(c.playbackPosition, const Duration(seconds: 3));
        await handler.play();
        await flush();
        expect(c.audible, isTrue);
        expect(player.starts, 2);
        expect(c.currentOccurrence!.occurrenceId, id);
        expect(player.sourceLoads, 1);
        expect(c.playbackPosition, const Duration(seconds: 3));
        await c.stop();
        await handler.dispose();
        c.dispose();
        await noisy.close();
        await interruptions.close();
      },
    );
  }
  test(
    'repeated Play and delayed stale states cannot duplicate native startup or undo Stop',
    () async {
      final player = DeferredStartPlayer();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: ControlledRepository(),
      );
      await c.playPlan(plan());
      await c.play();
      await c.play();
      expect(player.playRequests, 1);
      expect(c.paused, isFalse);
      final old = PlayerState(false, ProcessingState.ready);
      await c.stop();
      player.startGate.complete();
      await flush();
      player.states.add(old);
      await flush();
      player.emitReady(true);
      await flush();
      expect(player.active, isFalse);
      expect(player.starts, 0);
      expect(c.phase, QuranPlaybackPhase.idle);
      expect(c.hasActivePlayback, isFalse);
      c.dispose();
    },
  );
  testWidgets(
    'audio modal shows Preparing/Downloading, starts automatically, and reserves Resume for Pause',
    (tester) async {
      final player = DeferredStartPlayer(), repo = ProgressRepository();
      final first = repo.gates['112:2'] = Completer<void>();
      final rest = repo.gates['112:4'] = Completer<void>();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: repo,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioModal(
              controller: c,
              initialSurah: 112,
              initialFromAyah: 2,
              initialToAyah: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
      repo.progress['112:2']!(.4);
      await tester.pumpAndSettle();
      final downloading = find.text('Downloading');
      expect(downloading, findsOneWidget);
      final button = find.ancestor(
        of: downloading,
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      first.complete();
      await tester.pumpAndSettle();
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
      player.startGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(player.starts, 1);
      expect(c.offlineDownloading, isTrue);
      player.emitReady(false);
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
      player.emitReady(true);
      await tester.pumpAndSettle();
      rest.complete();
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
      expect(player.sourceLoads, 1);
      await tester.ensureVisible(find.text('Pause'));
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      player.emitReady(false);
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(player.starts, 2);
      expect(player.sourceLoads, 1);
      await tester.pumpWidget(const SizedBox());
      await c.stop();
      c.dispose();
    },
  );
  testWidgets(
    'reader transport labels preparation and actual pause consistently',
    (tester) async {
      final player = DeferredStartPlayer(), repo = ControlledRepository();
      final c = QuranAudioController.forTesting(
        player: player,
        repository: repo,
      );
      final gate = repo.gates['112:2'] = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: c,
              builder: (context, _) => ReaderAudioControls(
                portrait: true,
                palette: AppPalette.emerald,
                title: 'Al-Ikhlas',
                reference: '112:2',
                subtitle: c.statusLabel,
                playing: c.playing,
                paused: c.paused,
                preparingLabel: c.preparing && !c.paused ? c.statusLabel : null,
                onPrevious: c.seekPrevious,
                onNext: c.seekNext,
                onPlayPause: c.togglePlayPause,
                onSettings: () {},
                onStop: c.stop,
              ),
            ),
          ),
        ),
      );
      final starting = c.playPlan(plan());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Preparing'), findsOneWidget);
      expect(find.byTooltip('Resume'), findsNothing);
      gate.complete();
      await starting;
      player.startGate.complete();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Resume'), findsOneWidget);
      await tester.tap(find.byTooltip('Resume'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await c.stop();
      c.dispose();
    },
  );
}
