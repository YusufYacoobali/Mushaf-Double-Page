import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

void main() {
  late Directory imageDirectory;
  late File imageFile;

  setUpAll(() async {
    imageDirectory = await Directory.systemTemp.createTemp('mushaf_page_test_');
    imageFile = File('${imageDirectory.path}/page.png');
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final page = await picture.toImage(721, 1058);
    final bytes = await page.toByteData(format: ui.ImageByteFormat.png);
    await imageFile.writeAsBytes(bytes!.buffer.asUint8List());
    page.dispose();
    picture.dispose();
  });

  tearDownAll(() async {
    await imageDirectory.delete(recursive: true);
  });

  test('uses each printed mushaf native page aspect ratio', () {
    expect(
      QuranPageView.aspectRatioForMushaf('indopak_tajweed'),
      QuranPageView.pageAspectRatio,
    );
    expect(
      QuranPageView.aspectRatioForMushaf('madani'),
      closeTo(2096 / 3008, 1e-12),
    );
  });

  testWidgets('black margin toggles toolbar without stealing page taps', (
    tester,
  ) async {
    var backgroundTaps = 0;
    var pageTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: QuranPageView.singlePage(
            logicalPage: 4,
            pageScale: QuranPageView.minPageScalePortrait,
            imagePath: (_) => imageFile.path,
            isDarkMode: false,
            onTap: (_, _, _) => pageTaps++,
            onBackgroundTap: () => backgroundTaps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(backgroundTaps, 1);
    expect(pageTaps, 0);

    final screen = tester.getRect(find.byType(Scaffold));
    await tester.tapAt(screen.center);
    await tester.pump();
    expect(pageTaps, 1);
    expect(backgroundTaps, 1);
  });

  testWidgets('two-finger pinch still zooms the Quran page', (tester) async {
    final transformationController = TransformationController();
    var backgroundTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: QuranPageView.singlePage(
            logicalPage: 4,
            pageScale: QuranPageView.minPageScalePortrait,
            imagePath: (_) => imageFile.path,
            isDarkMode: false,
            onBackgroundTap: () => backgroundTaps++,
            transformationController: transformationController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getRect(find.byType(Scaffold)).center;
    final leftFinger = await tester.startGesture(
      center - const Offset(35, 0),
      pointer: 1,
    );
    final rightFinger = await tester.startGesture(
      center + const Offset(35, 0),
      pointer: 2,
    );
    await tester.pump();
    await leftFinger.moveTo(center - const Offset(110, 0));
    await rightFinger.moveTo(center + const Offset(110, 0));
    await tester.pump();

    expect(transformationController.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(
      transformationController.value.getMaxScaleOnAxis(),
      lessThanOrEqualTo(1 / QuranPageView.minPageScalePortrait + .001),
    );
    expect(backgroundTaps, 0);

    await leftFinger.up();
    await rightFinger.up();
    transformationController.dispose();
  });

  testWidgets('portrait toolbar zoom up to 100 percent stays centred', (
    tester,
  ) async {
    Widget readerAt(double scale) => MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: QuranPageView.singlePage(
          logicalPage: 4,
          pageScale: scale,
          imagePath: (_) => imageFile.path,
          isDarkMode: false,
          highlightRects: const [Rect.fromLTWH(0, 0, .1, .1)],
        ),
      ),
    );

    final pageSurface = find.byType(Image);

    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.runAsync(() async {
      final provider = FileImage(imageFile);
      await provider.evict();
      await precacheImage(provider, tester.element(find.byType(Scaffold)));
    });
    await tester.pumpWidget(readerAt(QuranPageView.minPageScalePortrait));
    await tester.pumpAndSettle();
    final minimumSize = tester.getRect(pageSurface).size;
    final minimumRect = tester.getRect(pageSurface);

    await tester.pumpWidget(readerAt(1.0));
    await tester.pumpAndSettle();
    final maximumSize = tester.getRect(pageSurface).size;
    final maximumRect = tester.getRect(pageSurface);

    final viewport = tester.getSize(find.byType(Scaffold));
    expect(minimumSize.width, closeTo(viewport.width, .001));
    expect(maximumSize.width, closeTo(viewport.width, .001));
    expect(minimumSize.height, closeTo(viewport.height * .7, .001));
    expect(maximumSize.height, closeTo(viewport.height, .001));
    expect(maximumSize.height, greaterThan(minimumSize.height + 20));
    expect(minimumRect.center, maximumRect.center);
  });

  testWidgets('old 120 percent zoom is capped at 100 percent', (tester) async {
    final transform = TransformationController();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.runAsync(() async {
      final provider = FileImage(imageFile);
      await provider.evict();
      await precacheImage(provider, tester.element(find.byType(Scaffold)));
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuranPageView.singlePage(
            logicalPage: 4,
            pageScale: 1.2,
            imagePath: (_) => imageFile.path,
            isDarkMode: false,
            transformationController: transform,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Image).first).height, closeTo(600, 1));
    final center = tester.getCenter(find.byType(Scaffold));
    final first = await tester.startGesture(
      center - const Offset(35, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(35, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-150, 0));
    await second.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(transform.value.getMaxScaleOnAxis(), lessThanOrEqualTo(1.0));
    await first.up();
    await second.up();
    await tester.pumpWidget(const SizedBox());
    transform.dispose();
  });

  Future<void> pumpReader(
    WidgetTester tester, {
    required ReaderPaging paging,
    Size size = const Size(400, 800),
    double scale = .7,
    required ValueChanged<int> onVisit,
    VoidCallback? onTap,
    VoidCallback? onBackgroundTap,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveQuranPages(
            paging: paging,
            layout: ReaderLayout.resolve(size: size),
            singleScale: scale,
            spreadScale: scale,
            imagePath: (_) => imageFile.path,
            isDarkMode: false,
            aspectRatio: QuranPageView.pageAspectRatio,
            highlightFor: (_) => [],
            highlightColor: Colors.amber,
            onPageChanged: onVisit,
            onFocus: (_) {},
            onTap: (_, _, _) => onTap?.call(),
            onBackgroundTap: onBackgroundTap,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reduced motion settles adjacent commands and swipes immediately',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final paging = ReaderPaging(initialPage: 2, lastPage: 6);
      final visits = <int>[];
      await pumpReader(tester, paging: paging, onVisit: visits.add);
      final command = paging.goTo(3, animate: true);
      await tester.pump();
      expect(paging.settled, isTrue);
      expect(await command, isTrue);
      expect(paging.visiblePages, [3]);
      await tester.dragFrom(const Offset(300, 400), const Offset(-250, 0));
      await tester.pump();
      expect(paging.settled, isTrue);
      expect(paging.visiblePages, [2]);
      expect(visits, [2]);
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
    },
  );

  testWidgets('page and margin taps resume after a programmatic turn', (
    tester,
  ) async {
    final paging = ReaderPaging(initialPage: 2, lastPage: 6);
    final visits = <int>[];
    var taps = 0, backgroundTaps = 0;
    await pumpReader(
      tester,
      paging: paging,
      onVisit: visits.add,
      onTap: () => taps++,
      onBackgroundTap: () => backgroundTaps++,
    );
    final navigation = paging.goTo(3, animate: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(paging.settled, isFalse);
    await tester.tapAt(const Offset(200, 400));
    await tester.tapAt(const Offset(10, 10));
    expect(taps, 0);
    expect(backgroundTaps, 0);
    await tester.pumpAndSettle();
    expect(await navigation, isTrue);
    expect(paging.visiblePages, [3]);
    await tester.tapAt(const Offset(200, 400));
    expect(taps, 1);
    await tester.tapAt(const Offset(10, 10));
    expect(taps, 1);
    expect(backgroundTaps, 1);
    expect(visits, isEmpty);
    await tester.pumpWidget(const SizedBox());
    paging.dispose();
  });

  testWidgets(
    'cancelled diagonal page turn preserves the zoomed vertical position',
    (tester) async {
      final paging = ReaderPaging(initialPage: 2, lastPage: 6);
      final visits = <int>[];
      await pumpReader(tester, paging: paging, onVisit: visits.add);
      final transform = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      transform.value = Matrix4.diagonal3Values(1.3, 1.3, 1);
      await tester.pumpAndSettle();
      await tester.timedDragFrom(
        const Offset(200, 400),
        const Offset(0, -70),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      final original = transform.value.clone();
      expect(original.storage[13], lessThan(0));
      final drag = await tester.startGesture(const Offset(80, 400));
      await drag.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await drag.moveBy(const Offset(65, -25));
      await tester.pump(const Duration(milliseconds: 500));
      expect(paging.phase, PageTurnPhase.dragging);
      expect(transform.value, original);
      await drag.up();
      await tester.pumpAndSettle();
      expect(transform.value, original);
      expect(paging.focusedPage, 2);
      expect(visits, isEmpty);
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
    },
  );

  for (final duringDrag in [false, true]) {
    testWidgets(
      'pinch zooms the live page when the second finger arrives ${duringDrag ? 'during a turn' : 'before a turn'}',
      (tester) async {
        final paging = ReaderPaging(initialPage: 2, lastPage: 6);
        final visits = <int>[];
        var taps = 0;
        await pumpReader(
          tester,
          paging: paging,
          onVisit: visits.add,
          onTap: () => taps++,
          onBackgroundTap: () => taps++,
        );
        final first = await tester.startGesture(
          const Offset(80, 400),
          pointer: 1,
        );
        if (duringDrag) {
          await first.moveBy(const Offset(75, 0));
          await tester.pump();
          expect(paging.settled, isFalse);
        }
        final second = await tester.startGesture(
          const Offset(220, 400),
          pointer: 2,
        );
        await tester.pump();
        await first.moveTo(const Offset(50, 400));
        await second.moveTo(const Offset(320, 400));
        await tester.pump();
        await first.moveBy(const Offset(-20, 0));
        await second.moveBy(const Offset(20, 0));
        await tester.pump();
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(
          viewer.transformationController!.value.getMaxScaleOnAxis(),
          greaterThan(1),
        );
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
        expect(paging.settled, isTrue);
        expect(paging.visiblePages, [2]);
        expect(visits, isEmpty);
        expect(taps, 0);
        await tester.pumpWidget(const SizedBox());
        paging.dispose();
      },
    );
  }

  for (final portrait in [false, true]) {
    for (var percent = portrait ? 70 : 60; percent <= 100; percent += 5) {
      testWidgets(
        '${portrait ? 'portrait' : 'landscape'} turns pages both ways at $percent percent',
        (tester) async {
          final paging = ReaderPaging(initialPage: 2, lastPage: 6);
          final visits = <int>[];
          await pumpReader(
            tester,
            paging: paging,
            size: portrait ? const Size(400, 800) : const Size(800, 400),
            scale: percent / 100,
            onVisit: visits.add,
          );
          final dx = portrait ? 300.0 : 600.0;
          await tester.dragFrom(const Offset(80, 200), Offset(dx, 0));
          await tester.pumpAndSettle();
          expect(paging.visiblePages, portrait ? [3] : [4, 5]);
          await tester.dragFrom(Offset(dx + 80, 200), Offset(-dx, 0));
          await tester.pumpAndSettle();
          expect(paging.visiblePages, portrait ? [2] : [2, 3]);
          if (!portrait && percent == 100) {
            final page = find.byKey(const ValueKey('quran-page-2'));
            final before = tester.getTopLeft(page).dy;
            await tester.dragFrom(
              const Offset(600, 300),
              const Offset(0, -200),
            );
            await tester.pumpAndSettle();
            expect(paging.visiblePages, [2, 3]);
            expect(tester.getTopLeft(page).dy, lessThan(before));
          }
          expect(visits, [portrait ? 3 : 4, 2]);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          paging.dispose();
        },
      );
    }
  }

  testWidgets('landscape toolbar zoom widens a top-centred spread', (
    tester,
  ) async {
    Widget readerAt(double scale) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 400)),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: QuranPageView.doublePage(
            spreadIndex: 0,
            pageScale: scale,
            totalPages: 2,
            imagePath: (_) => imageFile.path,
            isDarkMode: false,
          ),
        ),
      ),
    );

    final pages = find.byWidgetPredicate(
      (widget) =>
          widget is AspectRatio &&
          widget.aspectRatio == QuranPageView.pageAspectRatio,
    );

    await tester.pumpWidget(readerAt(QuranPageView.minPageScaleLandscape));
    await tester.pumpAndSettle();
    final minimumRect = tester.getRect(pages.first);

    await tester.pumpWidget(readerAt(QuranPageView.maxPageScaleLandscape));
    await tester.pumpAndSettle();
    final maximumRect = tester.getRect(pages.first);

    expect(maximumRect.width, greaterThan(minimumRect.width + 20));
    expect(minimumRect.top, 0);
    expect(maximumRect.top, 0);
  });
}
