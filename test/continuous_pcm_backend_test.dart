import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' show ProgressiveAudioSource;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/reader_audio_controls.dart';
import 'package:mushaf_two_page/logic/audio_playback_backend.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/pages/tasbeeh.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/audio_page_follower.dart';
import 'package:mushaf_two_page/utils/audio_vertical_follower.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';
import 'package:mushaf_two_page/utils/tasbeeh_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_test_fixtures.dart';

/// The native contract, with an explicitly advanced presentation clock. This
/// tests controller integration, not audible device output or codec fidelity.
class NativeClock {
  final events = StreamController<dynamic>.broadcast(sync: true);
  final calls = <MethodCall>[];
  final rows = <Map<String, Object>>[];
  final sources = <Map<String, Object>>[];
  final focus = <bool>[];
  late final backend = ContinuousPcmBackend(
    channel: const MethodChannel('test/quran/pcm'),
    events: events.stream,
    activateSession: (value) async {
      focus.add(value);
      return true;
    },
  );
  int generation = 0, frame = 0, total = 0;
  int framesPerRecording = 44100;
  bool finished = false;
  Completer<void>? prepareGate, stopGate;
  String? failMethod;
  Map<String, Object>? workerSnapshot;
  NativeClock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('test/quran/pcm'), (
          call,
        ) async {
          calls.add(call);
          final args = Map<String, dynamic>.from(call.arguments as Map);
          if (call.method == failMethod) {
            throw PlatformException(code: 'decoder');
          }
          if (call.method == 'snapshot') return workerSnapshot;
          if (call.method == 'prepare') {
            generation = args['generation'] as int;
            frame = args['seekFrames'] as int;
            total = 0;
            finished = false;
            rows.clear();
            sources.clear();
            for (final source in args['sources'] as List) {
              append(Map<String, Object>.from(source as Map));
            }
            await prepareGate?.future;
          } else if (call.method == 'enqueue') {
            append(Map<String, Object>.from(args)..remove('generation'));
          } else if (call.method == 'remove') {
            final ids = args['ids'] as List;
            sources.removeWhere((s) => ids.contains(s['id']));
            rows.removeWhere((s) => ids.contains(s['id']));
          } else if (call.method == 'finish') {
            finished = true;
          } else if (call.method == 'stop') {
            await stopGate?.future;
            sources.clear();
            rows.clear();
          }
          return null;
        });
  }
  void append(Map<String, Object> source) {
    sources.add(source);
    rows.add({
      'id': source['id']!,
      'start': total,
      'end': total + framesPerRecording,
      'decoded': framesPerRecording,
    });
    total += framesPerRecording;
  }

  int count(String method) => calls.where((c) => c.method == method).length;
  void clock(
    int value, {
    String state = 'ready',
    int? eventGeneration,
    int underruns = 0,
    String? error,
  }) {
    frame = value;
    events.add({
      'generation': eventGeneration ?? generation,
      'frames': value,
      'bufferedFrames': total,
      'rows': List.of(rows),
      'state': state,
      'underruns': underruns,
      if (error != null) 'error': error,
    });
  }

  Future<void> close() async {
    await events.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('test/quran/pcm'), null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativeClock native;
  late FakePlayer legacy;
  late ControlledRepository repository;
  late QuranAudioController controller;
  setUp(() {
    native = NativeClock();
    legacy = FakePlayer();
    repository = ControlledRepository();
    controller = QuranAudioController.forTesting(
      player: legacy,
      repository: repository,
      continuousBackend: native.backend,
      resolveIntroduction: fixtureIntroduction,
    );
  });
  tearDown(() async {
    if (native.prepareGate?.isCompleted == false) {
      native.prepareGate!.complete();
    }
    if (native.stopGate?.isCompleted == false) native.stopGate!.complete();
    await controller.stop();
    controller.dispose();
    await flush();
    await native.close();
  });

  test(
    'starts after the first recording while the next download is blocked',
    () async {
      repository.gates['112:3'] = Completer<void>();
      await controller.playPlan(plan());
      await flush();
      expect(controller.usingContinuousPcm, isTrue);
      expect(native.count('prepare'), 1);
      expect(native.count('play'), 1);
      expect(legacy.sourceLoads, 0);
      native.clock(100);
      expect(controller.currentAyah, 2);
      expect(controller.audible, isTrue);
      expect(native.sources, hasLength(1));
      repository.gates['112:3']!.complete();
      await flush();
      final starts = native.count('play'), pauses = native.count('pause');
      native.clock(44100);
      await flush();
      expect(controller.currentAyah, 3);
      expect(controller.playbackPosition, Duration.zero);
      expect(native.count('prepare'), 1);
      expect(native.count('play'), starts);
      expect(native.count('pause'), pauses);
    },
  );

  test(
    'rendered frames, not decoded or queued frames, select exact half-open boundaries',
    () async {
      await controller.playPlan(plan());
      await flush();
      native.clock(44099);
      expect(controller.currentAyah, 2);
      native.clock(44100);
      expect(controller.currentAyah, 3);
      expect(controller.currentMediaItem!.duration, const Duration(seconds: 1));
      expect(controller.bufferedPlaybackPosition, const Duration(seconds: 1));
      native.clock(88200);
      expect(controller.currentAyah, 4);
      expect(native.count('prepare'), 1);
      native.clock(132300, state: 'completed');
      await flush();
      expect(controller.phase, QuranPlaybackPhase.completed);
    },
  );

  for (final mode in [AudioRepeatMode.ayah, AudioRepeatMode.range]) {
    test(
      '$mode infinite repetition remains bounded through 350 transitions',
      () async {
        await controller.playPlan(
          plan(from: 1, to: 3, count: null, repeat: mode),
        );
        await flush();
        final expected = QuranPlaybackCursor(
          plan(from: 1, to: 3, count: null, repeat: mode),
          introductionForSurah: (_) => true,
        )..introduction = true;
        var at = 0;
        final seen = <String>{};
        for (var i = 0; i < 350; i++) {
          native.clock(at);
          await flush();
          expect(controller.currentItem!.key, expected.item.key);
          expect(controller.currentRepeat, expected.repetition);
          expect(seen.add(controller.currentOccurrence!.occurrenceId), isTrue);
          expect(native.sources.length, lessThanOrEqualTo(6));
          expect(controller.nativeQueueLength, lessThanOrEqualTo(6));
          expect(native.backend.timeline.length, lessThanOrEqualTo(6));
          expect(controller.usingContinuousPcm, isTrue);
          expect(expected.advance(), isTrue);
          at += 44100;
        }
        expect(native.count('prepare'), 1);
        expect(native.count('play'), 1);
        expect(legacy.starts, 0);
      },
    );
  }

  test(
    'all 22 reciters use the native backend for range, surah and queue plans',
    () async {
      for (final reciter in quranReciters) {
        for (final selection in [
          plan(reciter: reciter, surah: 55, from: 1, to: 10, count: 2),
          plan(reciter: reciter, surah: 2, from: 1, to: 286),
          plan(reciter: reciter, queue: [1, 9, 112]),
        ]) {
          await controller.playPlan(selection);
          await flush();
          native.clock(0);
          expect(controller.usingContinuousPcm, isTrue);
          expect(controller.plan, selection);
          expect(native.sources.length, inInclusiveRange(1, 6));
          expect(legacy.sourceLoads, 0);
        }
      }
    },
  );

  test(
    'verified Bismillah and queue boundaries follow the existing cursor',
    () async {
      final selection = plan(queue: [1, 9, 112], count: 2);
      await controller.playPlan(selection);
      await flush();
      final expected = QuranPlaybackCursor(
        selection,
        introductionForSurah: (_) => true,
      );
      var at = 0;
      var introductions = 0;
      do {
        native.clock(at);
        await flush();
        expect(controller.currentItem!.key, expected.item.key);
        if (controller.isIntroduction) {
          introductions++;
          expect(controller.currentSurah, 112);
        }
        at += 44100;
      } while (expected.advance());
      expect(introductions, 2);
      expect(native.finished, isTrue);
      expect(native.count('prepare'), 1);
    },
  );

  test(
    'background Pause and in-ayah seek preserve pause intent and finite EOF',
    () async {
      final handler = QuranAudioHandler(controller);
      await controller.playPlan(plan(to: 2));
      await flush();
      native.clock(2000);
      await handler.pause();
      expect(controller.paused, isTrue);
      final plays = native.count('play');
      await handler.seek(const Duration(milliseconds: 500));
      expect(native.finished, isTrue);
      expect(native.count('play'), plays);
      native.clock(22050);
      expect(controller.playbackPosition, const Duration(milliseconds: 500));
      expect(controller.paused, isTrue);
      await handler.play();
      await flush();
      expect(native.count('play'), plays + 1);
      await handler.dispose();
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform only probes eligible recordings and forwards their decisions',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        for (final reciter in quranReciters) {
          final path = '/audio/${reciter.id}/112:2.mp3';
          repository.invertedFiles.add(path);
          repository.stereoChecks.clear();
          await controller.playPlan(plan(reciter: reciter, to: 3));
          await flush();
          final eligible =
              platform == TargetPlatform.android &&
              reciter.id == 'abdullah_juhany';
          expect(
            repository.stereoChecks,
            eligible ? [path, '/audio/${reciter.id}/112:3.mp3'] : isEmpty,
            reason: reciter.id,
          );
          expect(native.sources.map((s) => s['polarity']), [
            eligible ? 'inverted' : null,
            null,
          ], reason: reciter.id);
        }
      },
    );
  }

  test(
    'decode failure disposes native output before fallback, preserving cursor and pause',
    () async {
      final selection = plan(
        to: 2,
        count: 4,
        reciter: quranReciters.firstWhere((r) => r.id == 'abdullah_juhany'),
      );
      repository.invertedFiles.add('/audio/${selection.reciter.id}/112:2.mp3');
      await controller.playPlan(selection);
      await flush();
      expect(native.sources.first['polarity'], 'inverted');
      native.clock(44100);
      await flush();
      final occurrence = controller.currentOccurrence;
      await controller.pause();
      final gate = native.stopGate = Completer<void>();
      native.events.add({
        'generation': native.generation,
        'error': 'future decoder failed',
      });
      await flush();
      expect(legacy.sourceLoads, 0);
      expect(legacy.starts, 0);
      gate.complete();
      native.stopGate = null;
      await flush();
      expect(controller.activeBackend, 'just_audio');
      expect(
        (legacy.sequence.first as ProgressiveAudioSource)
            .options!
            .invertRightChannel,
        isTrue,
      );
      expect(controller.currentOccurrence, occurrence);
      expect(controller.currentRepeat, 2);
      expect(controller.paused, isTrue);
      expect(controller.playbackPosition, Duration.zero);
      expect(
        controller.continuousFallbackReason,
        contains('future decoder failed'),
      );
      await controller.play();
      expect(legacy.starts, 1);
    },
  );

  test(
    'Pause during native preparation cannot be undone by a late ready event',
    () async {
      final gate = native.prepareGate = Completer<void>();
      final start = controller.playPlan(plan());
      await flush();
      await controller.pause();
      gate.complete();
      native.prepareGate = null;
      await start;
      await flush();
      native.clock(0);
      expect(controller.paused, isTrue);
      expect(native.count('play'), 0);
      await controller.play();
      await flush();
      expect(native.count('play'), 1);
    },
  );

  test(
    'Next and Previous preserve paused intent and use logical verse navigation',
    () async {
      await controller.playPlan(
        plan(count: null, repeat: AudioRepeatMode.ayah),
      );
      await flush();
      native.clock(44100);
      await controller.pause();
      final plays = native.count('play');
      await controller.seekNext();
      await flush();
      native.clock(0);
      expect(controller.currentItem!.ayah, 3);
      expect(controller.currentRepeat, 1);
      expect(controller.paused, isTrue);
      await controller.seekPrevious();
      await flush();
      native.clock(0);
      expect(controller.currentItem!.ayah, 2);
      expect(controller.paused, isTrue);
      expect(native.count('play'), plays);
      expect(legacy.sourceLoads, 0);
    },
  );

  test(
    'Pause while an in-ayah seek is preparing defeats its captured resume intent',
    () async {
      await controller.playPlan(plan(to: 2));
      await flush();
      native.clock(1000);
      final plays = native.count('play');
      final gate = native.prepareGate = Completer<void>();
      final seeking = controller.seek(const Duration(milliseconds: 500));
      await flush();
      await controller.pause();
      gate.complete();
      native.prepareGate = null;
      await seeking;
      await flush();
      expect(native.finished, isTrue);
      expect(native.count('play'), plays);
      expect(controller.paused, isTrue);
    },
  );

  test(
    'seek preparation failure hands the current occurrence to legacy output',
    () async {
      await controller.playPlan(plan());
      await flush();
      native.clock(5000);
      final occurrence = controller.currentOccurrence;
      native.failMethod = 'prepare';
      await controller.seek(const Duration(milliseconds: 500));
      await flush();
      expect(controller.activeBackend, 'just_audio');
      expect(controller.currentOccurrence, occurrence);
      expect(legacy.starts, 1);
    },
  );

  test(
    'missing native implementation falls back without changing selection',
    () async {
      native.failMethod = 'prepare';
      await controller.playPlan(plan(count: 3));
      await flush();
      expect(controller.activeBackend, 'just_audio');
      expect(controller.currentAyah, 2);
      expect(controller.plan!.repeatCount, 3);
      expect(legacy.starts, 1);
    },
  );

  test(
    'late generation events cannot undo Stop or navigate a new selection',
    () async {
      await controller.playPlan(plan());
      await flush();
      final old = native.generation;
      await controller.playPlan(plan(surah: 55, from: 5, to: 6));
      await flush();
      native.clock(44100, eventGeneration: old);
      native.clock(0);
      expect(controller.currentAyah, 5);
      await controller.stop();
      native.clock(44100, eventGeneration: old);
      expect(controller.phase, QuranPlaybackPhase.idle);
      expect(controller.hasActivePlayback, isFalse);
    },
  );

  test(
    'an error snapshot retries the latest rendered occurrence at its exact frame',
    () async {
      await controller.playPlan(plan(count: 2));
      await flush();
      native.clock(5000);
      expect(controller.currentAyah, 2);
      // The UI missed a boundary while busy. The native error carries the latest
      // played clock; handing off the previous UI cursor would repeat ayah 2.
      native.clock(44100 + 1000, error: 'decoder failed');
      await flush();
      expect(controller.usingContinuousPcm, isTrue);
      expect(native.frame, 1000);
      expect(controller.currentItem!.ayah, 3);
      expect(controller.currentRepeat, 1);
      expect(legacy.sourceLoads, 0);
      expect(native.count('prepare'), 2);
    },
  );

  test(
    'watchdog samples the worker before recovering a stalled UI clock',
    () async {
      controller.dispose();
      controller = QuranAudioController.forTesting(
        player: FakePlayer(),
        repository: repository,
        continuousBackend: native.backend,
        stallTimeout: const Duration(milliseconds: 100),
      );
      await controller.playPlan(plan());
      await flush();
      native.clock(200, state: 'buffering');
      native.workerSnapshot = {
        'generation': native.generation,
        'frames': 26000,
        'bufferedFrames': native.total,
        'rows': List.of(native.rows),
        'state': 'buffering',
      };
      Future<void> until(bool Function() predicate) async {
        while (!predicate()) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }

      // The platform receives the request before Flutter applies its reply.
      await native.backend.positionStream
          .firstWhere((position) => position.inMilliseconds == 589)
          .timeout(const Duration(seconds: 3));
      expect(native.count('snapshot'), greaterThanOrEqualTo(1));
      expect(native.count('prepare'), 1);
      expect(controller.playbackPosition.inMilliseconds, 589);
      // A second watchdog interval with exactly the same output and queue.
      await until(
        () => native.count('prepare') == 2,
      ).timeout(const Duration(seconds: 3));
      expect(native.frame, 26000);
      expect(native.count('snapshot'), greaterThanOrEqualTo(2));
    },
  );

  test(
    'a second native failure on the same occurrence hands off once',
    () async {
      await controller.playPlan(plan());
      await flush();
      native.clock(6500, error: 'route invalidated');
      await flush();
      native.clock(8000, error: 'decoder failed again');
      await flush();
      expect(native.count('prepare'), 2);
      expect(controller.usingContinuousPcm, isFalse);
      expect(legacy.sourceLoads, 1);
      expect(controller.playbackPosition, Duration.zero);
    },
  );

  test('long Al-Juhany selection resumes once and ends at true EOF', () async {
    // Actual decoded length of the pinned 2:282 reference in the source audit.
    native.framesPerRecording = 5516975;
    await controller.playPlan(
      plan(
        reciter: quranReciters.firstWhere((r) => r.id == 'abdullah_juhany'),
        surah: 2,
        from: 282,
        to: 282,
      ),
    );
    await flush();
    final first = native.generation;
    final occurrence = controller.currentOccurrence;
    const position = 1800001;
    native.clock(position, error: 'route invalidated');
    await flush();
    expect(native.frame, position);
    expect(native.generation, isNot(first));
    expect(controller.currentOccurrence, occurrence);
    expect(controller.currentRepeat, 1);
    native.clock(0, eventGeneration: first);
    native.clock(position + 1);
    expect(controller.playbackPosition.inSeconds, 40);
    native.clock(native.total, state: 'completed');
    await flush();
    expect(controller.phase, QuranPlaybackPhase.completed);
    expect(native.count('prepare'), 2);
    expect(legacy.sourceLoads, 0);
  });

  testWidgets(
    'recitation advances through turns and reveals only the latest settled ayah',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await PageAyahIndex.load();
        await controller.playPlan(plan(surah: 2, from: 5, to: 10));
        await flush();
      });
      final paging = ReaderPaging(initialPage: 4, lastPage: 624);
      final audioPages = AudioPageFollower();
      final measured = <(int, int)>[], commands = <(int, bool)>[];
      final manualCommits = <int>[];
      final vertical = AudioVerticalFollower(
        rectsFor: (page, surah, ayah, _) {
          measured.add((page, ayah));
          return page == 6 ? const [Rect.fromLTWH(.1, .9, .8, .06)] : [];
        },
      );
      void follow() => audioPages.followReader(
        audio: controller,
        paging: paging,
        vertical: vertical,
        visible: true,
        animate: true,
        mushaf: 'madani',
        onCommit: (page, changedSpread) => commands.add((page, changedSpread)),
      );
      void audioChanged() {
        WidgetsBinding.instance.addPostFrameCallback((_) => follow());
        WidgetsBinding.instance.ensureVisualUpdate();
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, bounds) {
                final layout = ReaderLayout.resolve(size: bounds.biggest);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AdaptiveQuranPages(
                      paging: paging,
                      layout: layout,
                      singleScale: .8,
                      spreadScale: 1,
                      imagePath: (_) => 'assets/mushaf/madani_preview.png',
                      isDarkMode: false,
                      aspectRatio: .69,
                      highlightFor: (_) => [],
                      highlightColor: Colors.amber,
                      mushaf: 'madani',
                      verticalFollower: vertical,
                      onFocus: (_) {},
                      onPageChanged: manualCommits.add,
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: ListenableBuilder(
                        listenable: controller,
                        builder: (context, _) => ReaderAudioControls(
                          palette: AppPalette.of(context),
                          portrait: layout.singlePage,
                          title: 'Al-Baqarah',
                          reference: '2:${controller.currentAyah}',
                          subtitle: '',
                          playing: controller.playing,
                          paused: controller.paused,
                          playbackActive: controller.hasActivePlayback,
                          onPrevious: controller.seekPrevious,
                          onPlayPause: controller.togglePlayPause,
                          onNext: controller.seekNext,
                          onStop: controller.stop,
                          onSettings: () {},
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final transport = [
        for (final action in ['prepare', 'play', 'pause', 'stop', 'seek'])
          native.count(action),
      ];
      expect(transport.take(2), [1, 1]);
      final pointer = await tester.startGesture(const Offset(540, 150));
      await pointer.moveBy(const Offset(45, 0));
      await tester.pump(const Duration(milliseconds: 80));
      expect(paging.phase, PageTurnPhase.dragging);
      controller.addListener(audioChanged);
      native.clock(4800); // 2:5 is on the opposite leaf of the committed 4/5.
      await tester.pump();
      expect(controller.audible, isTrue);
      expect(paging.focusedPage, 4);
      await tester.pump(const Duration(milliseconds: 150));
      await pointer.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(manualCommits, isEmpty);
      expect(commands, [(5, false)]);
      expect(paging.focusedPage, 5);

      measured.clear();
      native.clock(44100); // 2:6 starts a turn to 6/7.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(paging.phase, PageTurnPhase.settling);
      expect(paging.visiblePages, [4, 5]);
      expect(paging.pendingTarget, 6);
      native.clock(88200 + 5000); // 2:7 is already playing during that turn.
      await tester.pump();
      expect(controller.currentAyah, 7);
      expect(controller.playbackPosition, greaterThan(Duration.zero));
      expect(measured, isEmpty);
      await tester.pumpAndSettle();
      expect(commands, [(5, false), (6, true)]);
      expect(measured, contains((6, 7)));
      expect(measured.every((measurement) => measurement.$2 == 7), isTrue);

      // A new verse on the still-committed page can supersede an outward
      // command without recording another visit to that same page.
      final outward = paging.goTo(8, animate: true);
      native.clock(132300); // 2:8 is also on page 6.
      await tester.pumpAndSettle();
      expect(await outward, isFalse);
      expect(paging.focusedPage, 6);
      expect(commands, [(5, false), (6, true)]);

      await tester.dragFrom(const Offset(420, 120), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(manualCommits, [8]);
      native.clock(132300 + 12000);
      await tester.pump();
      expect(
        paging.focusedPage,
        8,
      ); // A position tick respects manual browsing.
      await paging.goTo(20);
      await tester.pumpAndSettle();
      await tester.runAsync(flush); // Allow the next recording to enqueue.
      native.clock(176400); // A distant audio target jumps directly.
      expect(controller.currentAyah, 9);
      await tester.pumpAndSettle();
      expect(commands, [(5, false), (6, true), (6, true)]);
      expect(paging.settled, isTrue);
      expect(paging.focusedPage, 6);
      expect(controller.audible, isTrue);
      final rotating = paging.goTo(8, animate: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(paging.phase, PageTurnPhase.settling);
      native.clock(176400 + 4400);
      final beforeResize = controller.playbackPosition;
      final occurrence = controller.currentOccurrence;
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      expect(await rotating, isTrue);
      expect(paging.singlePage, isTrue);
      expect(paging.focusedPage, 8);
      native.clock(176400 + 8800);
      await tester.pump();
      expect(controller.audible, isTrue);
      expect(controller.currentOccurrence, occurrence);
      expect(controller.playbackPosition, greaterThan(beforeResize));
      expect([
        for (final action in ['prepare', 'play', 'pause', 'stop', 'seek'])
          native.count(action),
      ], transport);
      expect(legacy.sourceLoads, 0);

      final turning = paging.goTo(9, animate: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(paging.phase, PageTurnPhase.settling);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(controller.paused, isTrue);
      expect(native.count('pause'), transport[2] + 1);
      expect(paging.phase, PageTurnPhase.settling);
      await tester.tap(find.byTooltip('Resume'));
      await tester.pump();
      expect(native.count('play'), transport[1] + 1);
      await tester.tap(find.byTooltip('Stop audio'));
      await tester.pump();
      expect(paging.phase, PageTurnPhase.settling);
      expect(native.count('stop'), transport[3] + 1);
      expect(controller.phase, QuranPlaybackPhase.idle);
      await tester.pumpAndSettle();
      expect(await turning, isTrue);
      expect(controller.hasActivePlayback, isFalse);
      controller.removeListener(audioChanged);
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
      vertical.dispose();
    },
  );

  testWidgets(
    'three short surahs keep their order through rapid Tasbeeh taps and transient buffering',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final writes = <String>[];
      final store = TasbeehStore(
        writeSnapshot: (value) async {
          writes.add(value);
          return true;
        },
      );
      await store.restore();
      await tester.pumpWidget(MaterialApp(home: TasbeehPage(store: store)));
      await tester.pumpAndSettle();
      final selection = plan(queue: [112, 113, 114]);
      await tester.runAsync(() async {
        await controller.playPlan(selection);
        await flush();
      });
      await tester.pump();
      final expected = QuranPlaybackCursor(
        selection,
        introductionForSurah: (_) => true,
      )..introduction = true;
      final seen = <String>{};
      var at = 0, count = 0, underruns = 0;
      do {
        await tester.runAsync(() async {
          native.clock(at, underruns: underruns);
          await flush();
        });
        await tester.pump();
        expect(controller.currentItem!.key, expected.item.key);
        expect(seen.add(controller.currentOccurrence!.occurrenceId), isTrue);
        for (var tap = 0; tap < 12; tap++) {
          await tester.tap(find.bySemanticsLabel('Count dhikr'));
          await tester.pump(const Duration(milliseconds: 8));
          count++;
        }
        final occurrence = controller.currentOccurrence;
        native.clock(at + 12000, state: 'buffering', underruns: ++underruns);
        expect(controller.phase, QuranPlaybackPhase.buffering);
        native.clock(at + 13000, underruns: underruns);
        expect(controller.currentOccurrence, occurrence);
        expect(controller.phase, QuranPlaybackPhase.playing);
        expect(controller.usingContinuousPcm, isTrue);
        at += 44100;
      } while (expected.advance());
      expect(store.count, BigInt.from(count));
      expect(writes.length, lessThan(count ~/ 4));
      expect(native.count('prepare'), 1);
      expect(native.count('play'), 1);
      expect(legacy.starts, 0);
      await tester.runAsync(() async {
        native.clock(at, state: 'completed', underruns: underruns);
        await flush();
      });
      await tester.pump();
      expect(controller.phase, QuranPlaybackPhase.completed);
      await tester.pumpWidget(const SizedBox());
      await store.flush();
      store.dispose();
    },
  );
}
