import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/progress/journey_store.dart';
import 'package:mushaf_two_page/progress/journey_tracking.dart';
import 'package:mushaf_two_page/progress/reading_progress_store.dart';
import 'package:mushaf_two_page/progress/progress_page.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('concurrent activity persists every event and distinct reach', () async {
    await Future.wait([
      for (var i = 0; i < 25; i++) JourneyStore.recordPages(2),
      for (var i = 0; i < 10; i++) JourneyStore.recordListen('112:1'),
      JourneyStore.recordListen('113:1'),
      JourneyStore.recordTranslation(),
      JourneyStore.recordTime(reading: 60, listening: 90),
      JourneyStore.recordDay(now: DateTime(2026, 9, 14), streak: 4),
      JourneyStore.recordDay(now: DateTime(2026, 9, 14), streak: 4),
      JourneyStore.recordDay(now: DateTime(2026, 9, 17), streak: 1),
    ]);
    final stats = await JourneyStore.load();
    expect(stats.pagesOpened, 50);
    expect(stats.ayahsListened, 11);
    expect(stats.uniqueAyahs, 2);
    expect(stats.surahsListened, 2);
    expect(stats.translationsRead, 1);
    expect(stats.activeDays, 2);
    expect(stats.bestStreak, 4);
    expect(stats.readingSeconds, 60);
    expect(stats.listeningSeconds, 90);
    expect(stats.since, isNotNull);
  });
  test(
    'old streak is retained as best without inventing historical totals',
    () async {
      SharedPreferences.setMockInitialValues({
        'reading_streak': 9,
        'reading_last_active': '2026-9-10',
      });
      final current = await ReadingProgressStore.load(
        now: DateTime(2026, 9, 14),
      );
      final stats = await JourneyStore.load();
      expect(current.streak, 0);
      expect(stats.bestStreak, 9);
      expect(stats.pagesOpened, 0);
      expect(stats.activeDays, 0);
      expect(stats.since, isNull);
      await ReadingProgressStore.recordReadingActivity(
        now: DateTime(2026, 9, 14),
      );
      expect((await JourneyStore.load()).bestStreak, 9);
    },
  );
  test(
    'rotation and rebuilds do not inflate visits; returning to a page counts',
    () {
      final tracker = PageVisitTracker();
      expect(tracker.show(['madani:1']), 1);
      expect(tracker.show(['madani:1']), 0);
      expect(tracker.show(['madani:1', 'madani:2']), 1);
      expect(tracker.show(['madani:2']), 0);
      expect(tracker.show(['madani:3']), 1);
      expect(tracker.show(['madani:2']), 1);
      expect(tracker.show(['indopak:2']), 1);
    },
  );
  test(
    'listens count actual playback, repeats and time but reject seeks and pauses',
    () {
      final listens = <String>[];
      var seconds = 0;
      final tracker = ListeningTracker(
        onListen: listens.add,
        onSeconds: (s) => seconds += s,
      );
      void sample(int ms, {bool playing = true, String id = 'a'}) =>
          tracker.sample(
            occurrence: id,
            verse: '112:1',
            position: Duration(milliseconds: ms),
            duration: const Duration(seconds: 10),
            playing: playing,
          );
      sample(0);
      sample(9500); // A seek is not nine seconds of listening.
      expect(listens, isEmpty);
      sample(0);
      for (var i = 1; i <= 5; i++) {
        sample(i * 1000);
      }
      sample(5000, playing: false);
      sample(5000, playing: false);
      sample(5000);
      for (var i = 6; i <= 10; i++) {
        sample(i * 1000);
      }
      expect(listens, ['112:1']);
      sample(
        10000,
      ); // Duplicate position/completion does not duplicate the listen.
      sample(0); // Same-ayah loop.
      for (var i = 1; i <= 10; i++) {
        sample(i * 1000);
      }
      sample(0, id: 'b'); // Next occurrence.
      sample(1000, id: 'b');
      tracker.reset();
      expect(listens, ['112:1', '112:1']);
      expect(seconds, 21);
    },
  );
  testWidgets(
    'translation exposure excludes offscreen text and deduplicates a visit',
    (tester) async {
      final seen = <String>{};
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 1200),
                  TranslationExposure(
                    verse: '2:7',
                    seen: seen,
                    child: const SizedBox(
                      height: 80,
                      child: Text('Translation'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect((await JourneyStore.load()).translationsRead, 0);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect((await JourneyStore.load()).translationsRead, 0);
      await tester.pump(const Duration(seconds: 1));
      expect((await JourneyStore.load()).translationsRead, 1);
      await tester.pump(const Duration(seconds: 5));
      expect((await JourneyStore.load()).translationsRead, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
    },
  );
  testWidgets('reader time excludes covered routes and flushes on disposal', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(
          body: ReaderActivity(pages: ['madani:1'], child: Text('Reader')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Settings')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    var stats = await JourneyStore.load();
    expect(stats.readingSeconds, 5);
    expect(stats.pagesOpened, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    stats = await JourneyStore.load();
    expect(stats.readingSeconds, inInclusiveRange(8, 9));
    expect(stats.pagesOpened, 1);
  });

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(320, 568),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('Journey stats layout fits $size dark=$dark', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final today = DateTime.now();
        SharedPreferences.setMockInitialValues({
          'reading_streak': 7,
          'reading_last_active': '${today.year}-${today.month}-${today.day}',
          JourneyStore.storageKey: jsonEncode({
            'pages': 1284,
            'listens': 368,
            'translations': 142,
            'readingSeconds': 18060,
            'appSeconds': 23000,
            'listeningSeconds': 9040,
            'days': List.generate(24, (i) => '$i'),
            'surahs': ['1', '2', '3', '4', '5'],
            'ayahs': List.generate(186, (i) => '2:$i'),
            'bestStreak': 12,
            'since': '2026-08-22',
          }),
        });
        await tester.runAsync(() async {
          await (FontLoader('Inter')..addFont(
                rootBundle.load(
                  'assets/fonts/Inter-VariableFont_opsz,wght.ttf',
                ),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: (dark ? AppPalette.blackDark : AppPalette.emerald)
                .toThemeData(),
            home: RepaintBoundary(key: key, child: const ProgressPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your Quran Journey'), findsOneWidget);
        expect(find.text('Current streak'), findsOneWidget);
        expect(find.text('Best streak'), findsOneWidget);
        expect(find.text('1,284'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('READER_PREVIEWS')) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/reader-previews/journey-${size.width.toInt()}-${dark ? 'dark' : 'ivory'}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.ensureVisible(find.text('Total app time'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
