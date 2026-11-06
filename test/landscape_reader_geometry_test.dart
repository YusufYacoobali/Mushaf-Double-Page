import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
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
          // Both pages share v4's vertical scroll; horizontal turns still reach PageView.
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
