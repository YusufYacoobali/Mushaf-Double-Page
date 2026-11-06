import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/pages/page_view.dart';

void main() {
  late Directory imageDirectory;
  late File imageFile;

  setUpAll(() async {
    imageDirectory = await Directory.systemTemp.createTemp('mushaf_page_test_');
    imageFile = File('${imageDirectory.path}/page.png');
    await imageFile.writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4'
        '2mP8/x8AAusB9Wl2nkwAAAAASUVORK5CYII=',
      ),
    );
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

    await tester.pumpWidget(readerAt(QuranPageView.minPageScalePortrait));
    await tester.pumpAndSettle();
    final minimumSize = tester.getSize(pageSurface);
    final minimumRect = tester.getRect(pageSurface);

    await tester.pumpWidget(readerAt(1.0));
    await tester.pumpAndSettle();
    final maximumSize = tester.getSize(pageSurface);
    final maximumRect = tester.getRect(pageSurface);

    expect(maximumSize.width, greaterThan(minimumSize.width + 20));
    expect(
      maximumSize.width / maximumSize.height,
      closeTo(QuranPageView.pageAspectRatio, .001),
    );
    expect(
      minimumSize.width / minimumSize.height,
      closeTo(QuranPageView.pageAspectRatio, .001),
    );
    expect(maximumSize.height, greaterThan(minimumSize.height + 20));
    expect(minimumRect.center, maximumRect.center);
  });

  testWidgets('old 120 percent zoom is capped at 100 percent', (tester) async {
    final transform = TransformationController();
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

  for (final portrait in [false, true]) {
    for (var percent = portrait ? 70 : 60; percent <= 100; percent += 5) {
      testWidgets(
        '${portrait ? 'portrait' : 'landscape'} turns pages both ways at $percent percent',
        (tester) async {
          tester.view.physicalSize = portrait
              ? const Size(400, 800)
              : const Size(800, 400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var page = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PageView.builder(
                  reverse: true,
                  itemCount: 3,
                  onPageChanged: (index) => page = index,
                  itemBuilder: (_, index) => portrait
                      ? QuranPageView.singlePage(
                          logicalPage: index,
                          pageScale: percent / 100,
                          imagePath: (_) => imageFile.path,
                          isDarkMode: false,
                          onTap: (_, _, _) {},
                        )
                      : QuranPageView.doublePage(
                          spreadIndex: index,
                          totalPages: 6,
                          pageScale: percent / 100,
                          imagePath: (_) => imageFile.path,
                          isDarkMode: false,
                          onTap: (_, _, _) {},
                        ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final dx = portrait ? 300.0 : 600.0;
          await tester.dragFrom(const Offset(80, 200), Offset(dx, 0));
          await tester.pumpAndSettle();
          expect(page, 1);
          await tester.dragFrom(Offset(dx + 80, 200), Offset(-dx, 0));
          await tester.pumpAndSettle();
          expect(page, 0);
          if (!portrait && percent == 100) {
            final before = tester.getTopLeft(find.byType(AspectRatio).first).dy;
            await tester.dragFrom(
              const Offset(400, 300),
              const Offset(0, -200),
            );
            await tester.pumpAndSettle();
            expect(page, 0);
            expect(
              tester.getTopLeft(find.byType(AspectRatio).first).dy,
              lessThan(before),
            );
          }
          expect(tester.takeException(), isNull);
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
