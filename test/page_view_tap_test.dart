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
    expect(backgroundTaps, 0);

    await leftFinger.up();
    await rightFinger.up();
    transformationController.dispose();
  });

  testWidgets('toolbar scale values visibly resize the portrait page', (
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
        ),
      ),
    );

    final pageSurface = find.byWidgetPredicate(
      (widget) =>
          widget is AspectRatio &&
          widget.aspectRatio == QuranPageView.pageAspectRatio,
    );

    await tester.pumpWidget(readerAt(QuranPageView.minPageScalePortrait));
    await tester.pumpAndSettle();
    final minimumSize = tester.getSize(pageSurface);

    await tester.pumpWidget(readerAt(QuranPageView.maxPageScalePortrait));
    await tester.pumpAndSettle();
    final maximumSize = tester.getSize(pageSurface);

    expect(maximumSize.width, greaterThan(minimumSize.width + 20));
    expect(maximumSize.height, greaterThan(minimumSize.height + 20));
  });
}
