import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/components/quran_page_turn_painter.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory images;
  setUpAll(() async {
    images = await Directory.systemTemp.createTemp('landscape_geometry_');
    for (final source in [
      ('indopak_tajweed', 721, 1058),
      ('madani', 131, 188),
    ]) {
      // Native-ratio fixtures ensure the actual painted Image has no letterbox.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final bounds = Rect.fromLTWH(
        0,
        0,
        source.$2.toDouble(),
        source.$3.toDouble(),
      );
      canvas.drawRect(bounds, Paint()..color = const Color(0xfffaf5e8));
      canvas.drawRect(
        bounds.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.black,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(source.$2, source.$3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${images.path}/${source.$1}.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    }
  });
  tearDownAll(() async => images.delete(recursive: true));

  QuranPageTurnPainter turn(WidgetTester tester) {
    final paint = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is QuranPageTurnPainter,
    );
    return tester.widget<CustomPaint>(paint).painter! as QuranPageTurnPainter;
  }

  testWidgets(
    'a later ayah on the incoming spread keeps the same turning sheet',
    (tester) async {
      final path = '${images.path}/indopak_tajweed.png';
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(
        () => precacheImage(
          FileImage(File(path)),
          tester.element(find.byType(SizedBox).last),
        ),
      );
      final paging = ReaderPaging(initialPage: 6, lastPage: 12);
      final visits = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveQuranPages(
            paging: paging,
            layout: ReaderLayout.resolve(size: const Size(800, 600)),
            singleScale: 1,
            spreadScale: 1,
            imagePath: (_) => path,
            isDarkMode: false,
            aspectRatio: QuranPageView.pageAspectRatio,
            highlightFor: (_) => [],
            highlightColor: Colors.amber,
            onPageChanged: visits.add,
            onFocus: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = paging.goTo(8, animate: true);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final sheet = turn(tester);
      expect(sheet.progress, inExclusiveRange(0, 1));
      final latest = paging.goTo(9, animate: true);
      await tester.pump();
      final retargeted = turn(tester);
      expect(retargeted.source, same(sheet.source));
      expect(retargeted.destination, same(sheet.destination));
      expect(retargeted.progress, greaterThanOrEqualTo(sheet.progress));
      await tester.pumpAndSettle();
      expect(await first, isFalse);
      expect(await latest, isTrue);
      expect(paging.focusedPage, 9);
      expect(visits, isEmpty);
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
    },
  );

  testWidgets(
    'turn freezes the scrolled page and its highlight until cancellation',
    (tester) async {
      const size = Size(800, 400);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final paging = ReaderPaging(initialPage: 6, lastPage: 12);
      final visits = <int>[];
      final reader = GlobalKey();
      const highlight = Rect.fromLTWH(.25, .45, .3, .1);
      var color = const Color(0xffff0000);
      late StateSetter update;
      final imagePath = '${images.path}/indopak_tajweed.png';
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(
        () => precacheImage(
          FileImage(File(imagePath)),
          tester.element(find.byType(SizedBox).last),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: reader,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return AdaptiveQuranPages(
                  paging: paging,
                  layout: ReaderLayout.resolve(size: size),
                  singleScale: 1,
                  spreadScale: 1,
                  imagePath: (_) => imagePath,
                  isDarkMode: false,
                  aspectRatio: QuranPageView.pageAspectRatio,
                  highlightFor: (page) => page == 6 ? [highlight] : [],
                  highlightColor: color,
                  onPageChanged: visits.add,
                  onFocus: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(600, 300), const Offset(0, -110));
      await tester.pumpAndSettle();
      final page = find.byKey(const ValueKey('quran-page-6'));
      final frame = tester.getRect(page);
      expect(frame.top, lessThan(-50));
      final sample =
          frame.topLeft +
          Offset(
            frame.width * highlight.center.dx,
            frame.height * highlight.center.dy,
          );

      Future<int> pixel(ui.Image image, Rect bounds) async {
        final x = ((sample.dx - bounds.left) / bounds.width * image.width)
            .floor();
        final y = ((sample.dy - bounds.top) / bounds.height * image.height)
            .floor();
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        return rgba.getUint32(4 * (image.width * y + x));
      }

      Future<int?> livePixel() => tester.runAsync(() async {
        final boundary =
            reader.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          return await pixel(image, Offset.zero & size);
        } finally {
          image.dispose();
        }
      });
      expect(await livePixel(), 0xff0000ff);
      final gesture = await tester.startGesture(const Offset(60, 240));
      await gesture.moveBy(const Offset(90, 0));
      await tester.pumpAndSettle();
      final initial = turn(tester);
      final right = initial.source.last;
      expect(right.bounds, frame);
      expect(
        await tester.runAsync(() => pixel(right.image!, right.bounds)),
        0xff0000ff,
      );

      update(() => color = const Color(0xff00ff00));
      await gesture.moveBy(const Offset(25, 0));
      await tester.pumpAndSettle();
      final updated = turn(tester);
      expect(updated.progress, greaterThan(initial.progress));
      expect(updated.source.last.image, same(right.image));
      expect(
        updated.destination.last.image,
        same(initial.destination.last.image),
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(paging.visiblePages, [6, 7]);
      expect(visits, isEmpty);
      expect(tester.getRect(page), frame);
      expect(await livePixel(), 0x00ff00ff);
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
    },
  );

  for (final edition in ['indopak_tajweed', 'madani']) {
    for (final size in [const Size(844, 390), const Size(915, 412)]) {
      for (final insets in [
        EdgeInsets.zero,
        const EdgeInsets.only(right: 24, bottom: 21),
      ]) {
        testWidgets('$edition v4 landscape rectangles at $size insets=$insets', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final paging = ReaderPaging(
            initialPage: 237,
            lastPage: edition == 'madani' ? 624 : 851,
          );
          final visits = <int>[];
          final taps = <(int, double, double)>[];
          final aspect = QuranPageView.aspectRatioForMushaf(edition);
          var expanded = false, zoom = .7;
          late StateSetter refresh;
          ReaderLayout? layout;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppPalette.emerald.toThemeData().copyWith(
                platform: TargetPlatform.android,
              ),
              builder: (context, child) {
                final media = MediaQuery.of(context);
                final padding = media.size.width > media.size.height
                    ? insets
                    : EdgeInsets.zero;
                return MediaQuery(
                  data: media.copyWith(padding: padding, viewPadding: padding),
                  child: child!,
                );
              },
              home: StatefulBuilder(
                builder: (context, update) {
                  refresh = update;
                  return Scaffold(
                    body: LayoutBuilder(
                      builder: (context, constraints) {
                        layout = ReaderLayout.resolve(
                          size: constraints.biggest,
                          padding: MediaQuery.paddingOf(context),
                          pageAspectRatio: aspect,
                        );
                        return Stack(
                          children: [
                            AdaptiveQuranPages(
                              paging: paging,
                              layout: layout!,
                              singleScale: .8,
                              spreadScale: zoom,
                              imagePath: (_) => '${images.path}/$edition.png',
                              isDarkMode: false,
                              aspectRatio: aspect,
                              highlightFor: (p) => p == 237
                                  ? const [Rect.fromLTWH(.2, .3, .4, .05)]
                                  : [],
                              highlightColor: Colors.amber,
                              onPageChanged: visits.add,
                              onFocus: (_) {},
                              onTap: (page, x, y) => taps.add((page, x, y)),
                            ),
                            Positioned.fromRect(
                              rect: layout!.controlsRegion,
                              child: MediaQuery.removePadding(
                                context: context,
                                removeTop: true,
                                removeBottom: true,
                                removeLeft: true,
                                removeRight: true,
                                child: Stack(
                                  children: [
                                    ReaderDock(
                                      placement: layout!.dockPlacement,
                                      expanded: expanded,
                                      onToggle: () =>
                                          refresh(() => expanded = !expanded),
                                      palette: AppPalette.emerald,
                                      zoom: ReaderZoom(
                                        portrait: layout!.bottomDock,
                                        palette: AppPalette.emerald,
                                        scale: zoom,
                                        minimum: .6,
                                        onDecrease: () =>
                                            refresh(() => zoom -= .05),
                                        onIncrease: () =>
                                            refresh(() => zoom += .05),
                                      ),
                                      actions: [
                                        for (var i = 0; i < 5; i++)
                                          IconButton(
                                            tooltip: 'Reader action $i',
                                            onPressed: () {},
                                            icon: const Icon(Icons.book),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(paging.visiblePages, [237]);
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(layout!.spreadLayout, ReaderSpreadLayout.centeredLandscape);
          expect(layout!.usableContentBounds, Offset.zero & size);
          expect(paging.visiblePages, [236, 237]);
          expect(paging.focusedPage, 237);
          expect(visits, isEmpty);
          Finder frame(int page) => find.byKey(ValueKey('quran-page-$page'));
          (Rect, Rect) rectangles() =>
              (tester.getRect(frame(237)), tester.getRect(frame(236)));
          void expectV4Geometry() {
            final (left, right) = rectangles();
            // Baseline from v4 (9cab9d5): full viewport, centred Row, 1 px gap.
            final expectedWidth = (size.width - 1) / 2 * zoom;
            expect(left.width, closeTo(expectedWidth, .01));
            expect(right.width, closeTo(expectedWidth, .01));
            expect(left.height, closeTo(expectedWidth / aspect, .01));
            expect(right.height, closeTo(expectedWidth / aspect, .01));
            expect(right.left - left.right, closeTo(1, .01));
            expect(
              left.expandToInclude(right).center.dx,
              closeTo(size.width / 2, .01),
            );
            expect(left.top, closeTo(0, .01));
            expect(right.top, closeTo(0, .01));
            expect(right.center.dx, greaterThan(left.center.dx));
            // Verify the actual Image render boxes, not only the frame metadata.
            for (final page in [236, 237]) {
              final image = find.descendant(
                of: frame(page),
                matching: find.byType(Image),
              );
              expect(tester.getRect(image), tester.getRect(frame(page)));
            }
          }

          expectV4Geometry();
          final initial = rectangles();
          await tester.tap(find.byTooltip('Open navigation'));
          await tester.pumpAndSettle();
          expect(rectangles(), initial);
          await tester.tap(find.byTooltip('Collapse navigation'));
          await tester.pumpAndSettle();
          expect(rectangles(), initial);
          expect(
            find.descendant(
              of: find.byType(AdaptiveQuranPages),
              matching: find.byType(SingleChildScrollView),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: frame(237), matching: find.byType(CustomPaint)),
            findsOneWidget,
          );
          final left = initial.$1;
          await tester.tapAt(
            Offset(left.left + left.width * .25, left.top + left.height * .25),
          );
          await tester.pump();
          expect(taps.single.$1, 237);
          expect(taps.single.$2, closeTo(.25, .001));
          expect(taps.single.$3, closeTo(.25, .001));
          for (final scale in [.6, 1.0]) {
            refresh(() => zoom = scale);
            await tester.pumpAndSettle();
            expectV4Geometry();
          }
          // Both pages scroll vertically together and still respond to horizontal turns.
          await tester.dragFrom(const Offset(100, 280), const Offset(0, -140));
          await tester.pumpAndSettle();
          final scrolled = rectangles();
          expect(scrolled.$1.top, lessThan(-50));
          expect(scrolled.$2.top, closeTo(scrolled.$1.top, .01));
          expect(scrolled.$2.left - scrolled.$1.right, closeTo(1, .01));
          expect(paging.visiblePages, [236, 237]);
          await tester.dragFrom(
            const Offset(80, 180),
            Offset(size.width * .7, 0),
          );
          await tester.pumpAndSettle();
          expect(paging.visiblePages, [238, 239]);
          await tester.dragFrom(
            Offset(size.width - 180, 120),
            Offset(-size.width * .7, 0),
          );
          await tester.pumpAndSettle();
          expect(paging.visiblePages, [236, 237]);
          final focusedLeft = tester.getRect(frame(237));
          await tester.tapAt(Offset(focusedLeft.center.dx, 80));
          await tester.pump();
          expect(paging.focusedPage, 237);
          final visitsBeforeRotation = List<int>.of(visits);
          tester.view.physicalSize = const Size(390, 844);
          await tester.pumpAndSettle();
          expect(paging.visiblePages, [237]);
          expect(paging.focusedPage, 237);
          expect(visits, visitsBeforeRotation);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          paging.dispose();
        });
      }
    }
  }
}
