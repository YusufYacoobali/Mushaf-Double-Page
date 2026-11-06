import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mushaf_two_page/components/audio_modal.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/audio_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_playback_test.dart'
    show FakePlayer, ControlledRepository, plan, fixtureIntroduction;
import 'package:mushaf_two_page/logic/audio_repository.dart';

void main() {
  testWidgets('Salah Bukhatir can be selected and restored', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = QuranAudioController.forTesting(
      player: FakePlayer(),
      resolveIntroduction: fixtureIntroduction,
      prepareSources: (_) async => [
        AudioSource.uri(Uri.parse('https://example.test/fixture.mp3')),
      ],
    );
    Widget modal() => MaterialApp(
      home: Scaffold(body: AudioModal(controller: controller, initialSurah: 1)),
    );
    await tester.pumpWidget(modal());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<Reciter>));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Salah Bukhatir'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Salah Bukhatir').hitTestable());
    await tester.pumpAndSettle();
    expect((await AudioPreferences.load())!.reciterId, 'salah_bukhatir');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(modal());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<Reciter>>(find.byType(DropdownButton<Reciter>))
          .value!
          .name,
      'Salah Bukhatir',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.stop();
  });

  for (final active in [false, true]) {
    testWidgets(
      'surah queue stays available from a single ayah, active=$active',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        await AudioPreferences.save(
          AudioPreferencesData(
            reciterId: quranReciters.first.id,
            surah: 2,
            fromAyah: 1,
            toAyah: 10,
            repeatCount: 3,
            repeatMode: AudioRepeatMode.range,
            sourceMode: AudioSourceMode.playlist,
            surahQueue: [2, 1],
          ),
        );
        final player = FakePlayer();
        final controller = QuranAudioController.forTesting(
          player: player,
          resolveIntroduction: fixtureIntroduction,
          prepareSources: (_) async => [
            AudioSource.uri(Uri.parse('https://example.test/fixture.mp3')),
          ],
        );
        if (active) {
          await controller.playPlan(
            AudioPlaybackPlan(
              reciter: quranReciters.first,
              surah: 2,
              fromAyah: 7,
              toAyah: 7,
              repeatCount: 1,
              repeatMode: AudioRepeatMode.range,
              sourceMode: AudioSourceMode.range,
            ),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AudioModal(
                controller: controller,
                initialSurah: 2,
                initialFromAyah: 7,
                initialToAyah: 7,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ayah 7-7'), findsOneWidget);
        expect(find.text('Ayah range'), findsOneWidget);
        final source = find.byType(DropdownButton<AudioSourceMode>);
        expect(source, findsOneWidget);
        expect(
          tester.getCenter(source).dy,
          closeTo(tester.getCenter(find.text('Ayah 7-7')).dy, 1),
        );
        expect(tester.getRect(source).bottom, lessThan(568));
        await tester.tap(source);
        await tester.pumpAndSettle();
        expect(find.text('Full surah').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Surah queue').hitTestable());
        await tester.pumpAndSettle();
        expect(find.text('Your listening queue'), findsOneWidget);
        expect(find.text('1. Al-Baqarah'), findsWidgets);
        expect(find.text('2. Al-Fatiha'), findsOneWidget);
        // Dismissing queue editing must keep the highlighted single-ayah mode.
        Navigator.of(tester.element(find.text('Your listening queue'))).pop();
        await tester.pumpAndSettle();
        expect(find.text('Ayah 7-7'), findsOneWidget);
        await tester.tap(source);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Surah queue').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save queue · 2 surahs'));
        await tester.pumpAndSettle();
        final saved = await AudioPreferences.load();
        expect(saved!.sourceMode, AudioSourceMode.playlist);
        expect(saved.surahQueue, [2, 1]);
        expect(find.text('2 surahs · Edit'), findsOneWidget);
        // Selecting a mode edits the plan without interrupting or starting audio.
        expect(player.starts, active ? 1 : 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.stop();
      },
    );
  }
  testWidgets(
    'failed introduction keeps recovery actions after modal reopening',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = ControlledRepository();
      repository.remainingFailures['112:bismillah'] = 10;
      repository.failures['112:bismillah'] = const AudioFailure(
        AudioFailureKind.missing,
        'Missing introduction',
      );
      final controller = QuranAudioController.forTesting(
        player: FakePlayer(),
        resolveIntroduction: fixtureIntroduction,
        repository: repository,
      );
      await controller.playPlan(plan(from: 1));
      Widget modal() => MaterialApp(
        home: Scaffold(
          body: AudioModal(controller: controller, initialSurah: 112),
        ),
      );
      await tester.pumpWidget(modal());
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Continue without Bismillah'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(modal());
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue without Bismillah'));
      await tester.tap(find.text('Continue without Bismillah'));
      await tester.pumpAndSettle();
      expect(controller.currentAyah, 1);
      expect(controller.error, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.stop();
      controller.dispose();
    },
  );
}
