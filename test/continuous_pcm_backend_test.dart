import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/audio_playback_backend.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';

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
  bool finished = false;
  Completer<void>? prepareGate, stopGate;
  String? failMethod;
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
      'end': total + 44100,
      'decoded': 44100,
    });
    total += 44100;
  }

  int count(String method) => calls.where((c) => c.method == method).length;
  void clock(int value, {String state = 'ready', int? eventGeneration}) {
    frame = value;
    events.add({
      'generation': eventGeneration ?? generation,
      'frames': value,
      'bufferedFrames': total,
      'rows': List.of(rows),
      'state': state,
      'underruns': 0,
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

  test(
    'decode failure disposes native output before fallback, preserving cursor and pause',
    () async {
      await controller.playPlan(plan(to: 2, count: 4));
      await flush();
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
}
