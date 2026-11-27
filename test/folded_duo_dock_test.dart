import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/main.dart';
import 'package:mushaf_two_page/utils/reader_highlight_preferences.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
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
          'reader_controls_arrow_only': arrowOnly,
        });
        await ReaderHighlightPreferences.save(
          const SavedReaderHighlight(
            mushaf: 'indopak_tajweed',
            page: 4,
            surah: 1,
            ayah: 1,
          ),
        );
        rootBundle.clear();
        await tester.pumpWidget(const MaterialApp(home: MyPDFViewer()));
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
        source.success({
          'width': 466,
          'height': 678,
          'closed': true,
          'divisions': [],
          'coverStrip': {'left': 382, 'top': 0, 'width': 84, 'height': 644},
          'coverObstructions': [
            {'left': 391, 'top': 0, 'width': 71, 'height': 180},
          ],
        });
        await tester.pumpAndSettle();
        expect(find.byType(NavigationPullTab), findsNothing);
        final rail = tester.getRect(
          find.byKey(tester.widget<ReaderDock>(dock).geometryKey!),
        );
        expect(rail.left, greaterThanOrEqualTo(strip.left));
        expect(rail.right, lessThanOrEqualTo(strip.right));
        expect(rail.top, greaterThanOrEqualTo(180));
        expect(rail.bottom, lessThanOrEqualTo(strip.bottom));
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
        expect(find.text('85%'), findsOneWidget);
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
  }
}
