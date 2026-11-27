import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/main.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'audio_test_fixtures.dart';
import 'package:mushaf_two_page/utils/ayah_rect_index.dart';
import 'package:mushaf_two_page/utils/reader_geometry_probe.dart';
import 'package:mushaf_two_page/utils/reader_highlight_preferences.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<MockStreamHandlerEventSink> openReader(
  WidgetTester tester,
  bool arrowOnly, {
  bool restoreSelection = false,
  QuranAudioController? audio,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(466, 678);
  tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(right: 84, bottom: 34);
  addTearDown(tester.view.reset);
  final docs = (await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('duo-cover-dock');
    final pages = await Directory('${dir.path}/indopak_tajweed').create();
    for (var i = 1; i <= 8; i++) {
      await File(
        'assets/mushaf/indopak_tajweed_preview.png',
      ).copy('${pages.path}/$i.webp');
    }
    return dir;
  }))!;
  addTearDown(() => tester.runAsync(() => docs.delete(recursive: true)));
  final messenger = tester.binding.defaultBinaryMessenger;
  const path = MethodChannel('plugins.flutter.io/path_provider');
  const channel = EventChannel('mushaf_two_page/display_regions');
  messenger.setMockMethodCallHandler(path, (_) async => docs.path);
  late MockStreamHandlerEventSink source;
  messenger.setMockStreamHandler(
    channel,
    MockStreamHandler.inline(
      onListen: (_, events) {
        source = events;
      },
    ),
  );
  addTearDown(() {
    messenger.setMockMethodCallHandler(path, null);
    messenger.setMockStreamHandler(channel, null);
  });
  SharedPreferences.setMockInitialValues({
    'CurrentPage1': 4,
    'quran_single_page_scale': 1.0,
    'reader_controls_arrow_only': arrowOnly,
  });
  if (restoreSelection) {
    await ReaderHighlightPreferences.save(
      const SavedReaderHighlight(
        mushaf: 'indopak_tajweed',
        page: 4,
        surah: 1,
        ayah: 1,
      ),
    );
  }
  rootBundle.clear();
  await tester.pumpWidget(
    MaterialApp(home: MyPDFViewer(audioController: audio)),
  );
  final dock = find.byType(ReaderDock);
  for (var n = 0; n < 400 && dock.evaluate().isEmpty; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(dock, findsOneWidget);
  expect(
    find.byTooltip(arrowOnly ? 'Open navigation' : 'Collapse navigation'),
    findsOneWidget,
  );
  return source;
}

Future<void> fold(
  WidgetTester tester,
  MockStreamHandlerEventSink source,
) async {
  source.success({
    'width': 466,
    'height': 678,
    'closed': true,
    'divisions': [],
    'coverStrip': {'left': 382, 'top': 0, 'width': 84, 'height': 644},
    'coverObstructions': [
      {'left': 382, 'top': 0, 'width': 84, 'height': 82},
    ],
  });
  await tester.pumpAndSettle();
  expect(find.byType(NavigationPullTab), findsNothing);
}

Future<void> unfold(
  WidgetTester tester,
  MockStreamHandlerEventSink source,
) async {
  source.success({
    'width': 669,
    'height': 951,
    'closed': false,
    'divisions': [],
  });
  tester.view.physicalSize = const Size(669, 951);
  tester.view.padding = const FakeViewPadding(bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(bottom: 34);
  await tester.pumpAndSettle();
}

void main() {
  const size = Size(466, 678);
  const padding = EdgeInsets.only(right: 84, bottom: 34);
  const strip = Rect.fromLTRB(382, 0, 466, 644);
  test(
    'closed cover uses the largest clear interval without moving the page',
    () {
      final ordinary = ReaderLayout.resolve(
        size: size,
        padding: padding,
        foldedCover: true,
        iosPhoneWidePortrait: true,
      );
      final obstructions = [
        const Rect.fromLTRB(380, -5, 465, 100),
        const Rect.fromLTRB(435, 270, 480, 305),
      ];
      ReaderLayout resolve({
        bool closed = true,
        bool ipad = false,
        bool ios = true,
        Rect area = strip,
        List<Rect>? blocked,
      }) => ReaderLayout.resolve(
        size: size,
        padding: padding,
        foldedCover: closed,
        iosPhoneWidePortrait: ios,
        preserveLegacyIPadPortrait: ipad,
        nativeCoverStrip: area,
        coverObstructions: blocked ?? obstructions,
      );
      final cover = resolve();
      expect(cover.foldedDockRegion, const Rect.fromLTRB(398, 305, 450, 644));
      expect(cover.pageRegions, ordinary.pageRegions);
      expect(cover.usableContentBounds, ordinary.usableContentBounds);
      expect(cover.controlsRegion, ordinary.controlsRegion);
      expect(cover.sizing, ordinary.sizing);
      expect(resolve(closed: false).foldedDockRegion, isNull);
      expect(resolve(ipad: true).foldedDockRegion, isNull);
      expect(resolve(ios: false).foldedDockRegion, isNull);
      expect(resolve(blocked: [strip]).foldedDockRegion, isNull);
      expect(
        resolve(area: const Rect.fromLTWH(456, 0, 10, 644)).foldedDockRegion,
        isNull,
      );
    },
  );

  for (final arrowOnly in [true, false]) {
    testWidgets(
      'folded reader keeps controls through idle, taps and selection, restoring arrow-only=$arrowOnly on unfolding',
      (tester) async {
        final source = await openReader(
          tester,
          arrowOnly,
          restoreSelection: true,
        );
        final dock = find.byType(ReaderDock);
        await fold(tester, source);
        final rail = tester.getRect(
          find.byKey(tester.widget<ReaderDock>(dock).geometryKey!),
        );
        expect(rail.left, greaterThanOrEqualTo(strip.left));
        expect(rail.right, lessThanOrEqualTo(strip.right));
        expect(rail.top, greaterThanOrEqualTo(82));
        expect(rail.bottom, lessThanOrEqualTo(strip.bottom));
        expect(find.text('100%'), findsOneWidget);
        final minus = find.byTooltip('Zoom out');
        // The native capture also exercises zoom while an ayah is selected.
        expect(minus.hitTestable(), findsOneWidget);
        await tester.tapAt(tester.getCenter(minus));
        await tester.pumpAndSettle();
        expect(find.text('95%'), findsOneWidget);
        final bookmark = find.byTooltip('Save ayah');
        await tester.ensureVisible(bookmark);
        await tester.pumpAndSettle();
        await tester.tap(bookmark);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Remove ayah bookmark'), findsOneWidget);
        // Tap the blank upper reading margin once to clear selection and again to
        // exercise the usual navigation toggle.
        await tester.tapAt(const Offset(4, 6));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(4, 6));
        await tester.pump(const Duration(seconds: 12));
        await tester.pumpAndSettle();
        expect(find.byType(NavigationPullTab), findsNothing);
        expect(find.byTooltip('Zoom in').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pumpAndSettle();
        expect(find.text('100%'), findsOneWidget);
        await unfold(tester, source);
        if (arrowOnly) {
          expect(find.byTooltip('Open navigation'), findsOneWidget);
          expect(find.byTooltip('Zoom in'), findsNothing);
          await tester.tap(find.byTooltip('Open navigation'));
          await tester.pumpAndSettle();
        }
        expect(find.byTooltip('Collapse navigation'), findsOneWidget);
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Open navigation'), findsOneWidget);
        expect(
          (await SharedPreferences.getInstance()).getBool(
            'reader_controls_arrow_only',
          ),
          arrowOnly,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    for (final playback in [false, true]) {
      testWidgets(
        'unfold with ${playback ? "playback" : "selection"} started on the pinned dock, arrow-only=$arrowOnly',
        (tester) async {
          final player = FakePlayer();
          final audio = QuranAudioController.forTesting(
            player: player,
            repository: ControlledRepository(),
          );
          addTearDown(audio.dispose);
          final source = await openReader(tester, arrowOnly, audio: audio);
          await tester.pump(const Duration(seconds: 11));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Open navigation'), findsOneWidget);
          await fold(tester, source);
          await tester.tap(find.byTooltip('Zoom out'));
          await tester.pumpAndSettle();
          final page = find.byKey(const ValueKey('quran-page-4'));
          if (playback) {
            await audio.playPlan(plan(surah: 1, from: 3, to: 4));
            await tester.pump();
            expect(audio.audible, isTrue);
            player.at = const Duration(seconds: 2);
          } else {
            final rect = tester.getRect(page);
            final ayah = AyahRectIndex.rectsFor(4, 1, 3).first.center;
            await tester.tapAt(
              rect.topLeft +
                  Offset(ayah.dx * rect.width, ayah.dy * rect.height),
            );
            await tester.pumpAndSettle();
            expect(find.byTooltip('Save ayah'), findsOneWidget);
          }

          final session = audio.playbackSessionId;
          await unfold(tester, source);
          final reader = tester.widget<ReaderGeometryProbe>(
            find.byType(ReaderGeometryProbe),
          );
          expect(reader.focusedPage, 4);
          expect(reader.zoom, .95);
          expect(page, findsOneWidget);
          if (arrowOnly) {
            expect(find.byTooltip('Open navigation'), findsOneWidget);
            await tester.tap(find.byTooltip('Open navigation'));
            await tester.pumpAndSettle();
          }
          expect(find.text('95%'), findsOneWidget);
          if (playback) {
            expect(audio.playbackSessionId, session);
            expect(audio.audible, isTrue);
            expect(audio.currentAyah, 3);
            expect(player.position, const Duration(seconds: 2));
            expect(player.sourceLoads, 1);
            await tester.pump(const Duration(seconds: 11));
            expect(find.byTooltip('Stop audio'), findsOneWidget);
            expect(find.byTooltip('Stop audio'), findsOneWidget);
            await audio.stop();
          } else {
            if (!arrowOnly) {
              await tester.pump(const Duration(seconds: 11));
              await tester.pumpAndSettle();
            }
            expect(find.byTooltip('Save ayah'), findsOneWidget);
            expect(
              (await ReaderHighlightPreferences.load('indopak_tajweed'))?.ayah,
              3,
            );
            await tester.tapAt(const Offset(4, 6));
            await tester.pump();
          }
          await tester.pump(const Duration(seconds: 11));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Open navigation'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }
}
