import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/audio_modal.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_test_fixtures.dart';
import 'mp3quran_pilot_test.dart'
    show PilotRepository, ContinuousPlayer, selection;

void main() {
  late ContinuousPlayer player;
  late PilotRepository pilot;
  late ControlledRepository everyAyah;
  late QuranAudioController controller;
  void initialize() {
    SharedPreferences.setMockInitialValues({});
    player = ContinuousPlayer()..durationOverride = const Duration(seconds: 34);
    pilot = PilotRepository();
    everyAyah = ControlledRepository();
    controller = QuranAudioController.forTesting(
      player: player,
      repository: everyAyah,
      continuousRepository: pilot,
      continuousEnabled: true,
      resolveIntroduction: fixtureIntroduction,
    );
  }

  tearDown(() async {
    await controller.stop();
    controller.dispose();
  });
  Future<void> modal(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AudioModal(controller: controller, initialSurah: 67),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'indicator waits for native install, then follows fallback and fresh playback',
    (tester) async {
      initialize();
      pilot.gate = Completer<void>();
      final pending = controller.playPlan(selection());
      await modal(tester);
      expect(controller.usingContinuousAudio, isTrue);
      expect(controller.nativeProvider, isNull);
      expect(find.text('Audio source: No active source'), findsOneWidget);
      pilot.gate!.complete();
      await tester.pumpAndSettle();
      expect(controller.nativeProvider, QuranAudioProvider.mp3QuranContinuous);
      await pending;
      expect(find.text('Audio source: MP3Quran (continuous)'), findsOneWidget);
      expect(controller.nativeProvider, QuranAudioProvider.mp3QuranContinuous);

      // Editing Full Surah to Range leaves the installed native recording intact.
      await tester.tap(find.byType(DropdownButton<AudioSourceMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ayah range').last);
      await tester.pumpAndSettle();
      expect(find.text('Audio source: MP3Quran (continuous)'), findsOneWidget);
      expect(player.sourceLoads, 1);

      await controller.pause();
      player.fail();
      await tester.pumpAndSettle();
      expect(find.text('Audio source: EveryAyah (fallback)'), findsOneWidget);
      expect(controller.paused, isTrue);
      final navigation = controller.seekNext();
      await tester.pumpAndSettle();
      await navigation;
      expect(find.text('Audio source: EveryAyah (fallback)'), findsOneWidget);
      final normal = controller.playPlan(selection(surah: 66));
      await tester.pumpAndSettle();
      await normal;
      expect(find.text('Audio source: EveryAyah (normal)'), findsOneWidget);
      await controller.stop();
      await tester.pumpAndSettle();
      expect(find.text('Audio source: No active source'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'download failure reports fallback only after EveryAyah native load',
    (tester) async {
      initialize();
      pilot.fail = true;
      everyAyah.gates['67:bismillah'] = Completer<void>();
      final pending = controller.playPlan(selection());
      await modal(tester);
      expect(find.text('Audio source: No active source'), findsOneWidget);
      expect(find.text('Audio source: MP3Quran (continuous)'), findsNothing);
      everyAyah.gates['67:bismillah']!.complete();
      await tester.pumpAndSettle();
      await pending;
      expect(find.text('Audio source: EveryAyah (fallback)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'missing manifest is an actual EveryAyah fallback for an opted-in eligible request',
    () async {
      initialize();
      final c = QuranAudioController.forTesting(
        player: ContinuousPlayer(),
        repository: everyAyah,
        continuousRepository: PilotRepository(available: false),
        continuousEnabled: true,
        resolveIntroduction: fixtureIntroduction,
      );
      await c.playPlan(selection());
      expect(c.nativeProvider, QuranAudioProvider.everyAyahFallback);
      await c.stop();
      c.dispose();
    },
  );

  test('native source failure before install never reports MP3Quran', () async {
    initialize();
    player.failLoads = 1;
    final seen = <QuranAudioProvider?>[];
    controller.addListener(() => seen.add(controller.nativeProvider));
    await controller.playPlan(selection());
    await flush();
    expect(seen, isNot(contains(QuranAudioProvider.mp3QuranContinuous)));
    expect(controller.nativeProvider, QuranAudioProvider.everyAyahFallback);
  });

  test(
    'replacement invalidates late provider installation and resets fallback',
    () async {
      initialize();
      pilot.gate = Completer<void>();
      final pending = controller.playPlan(selection());
      await flush();
      await controller.playPlan(selection(surah: 66));
      pilot.gate!.complete();
      await pending;
      expect(controller.nativeProvider, QuranAudioProvider.everyAyah);
      await controller.stop();
      expect(controller.nativeProvider, isNull);
    },
  );
}
