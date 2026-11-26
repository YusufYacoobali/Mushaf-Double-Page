import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/navigator.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

// Geometry baseline: 9cab9d5ce3d2c3d0e44d51bb4ac336126362f740.
// v4 singlePage: full viewport width, viewport height * zoom, centred vertically.
// v4 ReaderDock: bottom 16 collapsed; max(16, safe.bottom) expanded, with a
// 24 px tab above 54 px of navigation and optionally 56 px of context controls.
// v4 navigator: right-aligned 320 px Material, full screen height; SafeArea is
// inside the background, with minimum top/bottom padding of 12 px.
void main() {
  late Directory images;
  setUpAll(() async {
    images = await Directory.systemTemp.createTemp('iphone_geometry_');
    for (final source in [
      ('indopak_tajweed', 721, 1058),
      ('madani', 131, 188),
    ]) {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xfffaf5e8), BlendMode.src);
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
    for (final device in [
      (const Size(375, 812), const FakeViewPadding(top: 44, bottom: 34)),
      (const Size(393, 852), const FakeViewPadding(top: 59, bottom: 34)),
      (const Size(430, 932), const FakeViewPadding(top: 59, bottom: 34)),
    ]) {
      testWidgets('$edition v4 portrait geometry at ${device.$1}', (
        tester,
      ) async {
        final (size, insets) = device;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.padding = insets;
        tester.view.viewPadding = insets;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        final paging = ReaderPaging(
          initialPage: 237,
          lastPage: edition == 'madani' ? 624 : 851,
        );
        final visits = <int>[];
        final taps = <(int, double, double)>[];
        var expanded = false, contextual = false, zoom = .7;
        late StateSetter refresh;
        late ReaderLayout layout;
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.runAsync(
          () => precacheImage(
            FileImage(File('${images.path}/$edition.png')),
            tester.element(find.byType(Scaffold)),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppPalette.emerald.toThemeData().copyWith(
              platform: TargetPlatform.iOS,
            ),
            home: StatefulBuilder(
              builder: (context, update) {
                refresh = update;
                return Scaffold(
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      layout = ReaderLayout.resolve(
                        size: constraints.biggest,
                        padding: MediaQuery.paddingOf(context),
                        displayFeatures: MediaQuery.displayFeaturesOf(context),
                        pageAspectRatio: QuranPageView.aspectRatioForMushaf(
                          edition,
                        ),
                      );
                      return Stack(
                        children: [
                          AdaptiveQuranPages(
                            paging: paging,
                            layout: layout,
                            singleScale: zoom,
                            spreadScale: .7,
                            imagePath: (_) => '${images.path}/$edition.png',
                            isDarkMode: false,
                            aspectRatio: QuranPageView.aspectRatioForMushaf(
                              edition,
                            ),
                            highlightFor: (page) => page == 237
                                ? const [Rect.fromLTWH(.2, .3, .4, .05)]
                                : [],
                            highlightColor: Colors.amber,
                            onPageChanged: visits.add,
                            onFocus: (_) {},
                            onTap: (page, x, y) => taps.add((page, x, y)),
                          ),
                          // The exact composition used by main.dart, including
                          // the coordinate system and inherited system insets.
                          ReaderDockOverlay(
                            layout: layout,
                            child: ReaderDock(
                              placement: layout.dockPlacement,
                              expanded: expanded,
                              onToggle: () =>
                                  refresh(() => expanded = !expanded),
                              palette: AppPalette.emerald,
                              zoom: ReaderZoom(
                                portrait: layout.bottomDock,
                                palette: AppPalette.emerald,
                                scale: zoom,
                                minimum: .7,
                                onDecrease: () {},
                                onIncrease: () {},
                              ),
                              actions: [
                                IconButton(
                                  tooltip: 'Surah navigator',
                                  icon: const Icon(Icons.menu_book),
                                  onPressed: () => SurahJuzNavigator.show(
                                    context: context,
                                    onJumpToPage: (_) {},
                                    mushaf: edition,
                                    currentLogicalPage: 237,
                                  ),
                                ),
                              ],
                              contextControls: contextual
                                  ? const SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                    )
                                  : null,
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
        final page = find.byKey(const ValueKey('quran-page-237'));
        void expectPage(double scale) {
          final expected = Rect.fromLTWH(
            0,
            size.height * (1 - scale) / 2,
            size.width,
            size.height * scale,
          );
          final frame = tester.getRect(page);
          expect(frame.left, closeTo(expected.left, .001));
          expect(frame.top, closeTo(expected.top, .001));
          expect(frame.width, closeTo(expected.width, .001));
          expect(frame.height, closeTo(expected.height, .001));
          // Measure the transformed image itself, not just a full-width wrapper:
          // contain/letterbox regressions must fail even if the frame is correct.
          final image = tester.getRect(
            find.descendant(of: page, matching: find.byType(Image)),
          );
          expect(image.left, closeTo(frame.left, .001));
          expect(image.top, closeTo(frame.top, .001));
          expect(image.width, closeTo(frame.width, .001));
          expect(image.height, closeTo(frame.height, .001));
          final paint = find.descendant(
            of: page,
            matching: find.byType(CustomPaint),
          );
          expect(tester.getRect(paint), frame);
          expect(
            paint,
            paints..rrect(
              rrect: RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  frame.width * .2,
                  frame.height * .3,
                  frame.width * .4,
                  frame.height * .05,
                ),
                const Radius.circular(4),
              ),
              color: Colors.amber,
            ),
          );
          expect(
            tester
                .widget<InteractiveViewer>(find.byType(InteractiveViewer))
                .maxScale,
            closeTo(1 / scale, .001),
          );
        }

        for (final withContext in [false, true]) {
          refresh(() => contextual = withContext);
          for (final scale in [.7, .8, 1.0]) {
            refresh(() => zoom = scale);
            await tester.pumpAndSettle();
            expectPage(scale);
            final collapsed = tester.getRect(find.byType(NavigationPullTab));
            expect(collapsed.bottom, closeTo(size.height - 16, .001));
            expect(collapsed.height, 24);
            final frame = tester.getRect(page);
            await tester.tapAt(
              Offset(frame.width * .25, frame.top + frame.height * .35),
            );
            await tester.pump();
            expect(taps.last.$1, 237);
            expect(taps.last.$2, closeTo(.25, .001));
            expect(taps.last.$3, closeTo(.35, .001));
            await tester.tap(find.byTooltip('Open navigation'));
            await tester.pumpAndSettle();
            expectPage(scale);
            final tab = tester.getRect(find.byType(NavigationPullTab));
            expect(
              tab.bottom,
              closeTo(
                size.height - insets.bottom - 54 - (withContext ? 56 : 0),
                .001,
              ),
            );
            final panel = tester.getRect(
              find.byKey(
                ValueKey(
                  withContext
                      ? 'reader-context-panel'
                      : 'reader-navigation-panel',
                ),
              ),
            );
            expect(panel.left, 10);
            expect(panel.right, size.width - 10);
            expect(panel.bottom, closeTo(size.height - insets.bottom, .001));
            final navigation = tester.getRect(
              find.byKey(const ValueKey('reader-navigation-panel')),
            );
            expect(navigation.height, 56);
            expect(
              navigation.bottom,
              closeTo(
                size.height - insets.bottom - (withContext ? 56 : 0),
                .001,
              ),
            );
            await tester.tap(find.byTooltip('Collapse navigation'));
            await tester.pumpAndSettle();
            expect(tester.getRect(find.byType(NavigationPullTab)), collapsed);
          }
        }

        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Surah navigator'));
        await tester.pumpAndSettle();
        void expectNavigator() {
          expect(
            tester.getRect(find.byKey(const ValueKey('surah-juz-panel'))),
            Rect.fromLTWH(size.width - 320, 0, 320, size.height),
          );
          final contents = tester.getRect(
            find.byKey(const ValueKey('surah-juz-content')),
          );
          expect(contents.top, insets.top);
          expect(contents.bottom, size.height - insets.bottom);
        }

        expectNavigator();
        await tester.tap(find.text('Juz'));
        await tester.pumpAndSettle();
        expectNavigator();
        await tester.tapAt(const Offset(10, 200));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('surah-juz-panel')), findsNothing);
        refresh(() => expanded = false);
        await tester.pumpAndSettle();
        tester.view.physicalSize = Size(size.height, size.width);
        tester.view.padding = FakeViewPadding(
          left: insets.top,
          right: insets.top,
          bottom: 21,
        );
        tester.view.viewPadding = tester.view.padding;
        await tester.pumpAndSettle();
        expect(paging.visiblePages, [236, 237]);
        expect(paging.focusedPage, 237);
        tester.view.physicalSize = size;
        tester.view.padding = insets;
        tester.view.viewPadding = insets;
        await tester.pumpAndSettle();
        expectPage(1);
        expect(
          tester.getRect(find.byType(NavigationPullTab)).bottom,
          closeTo(size.height - 16, .001),
        );
        expect(paging.focusedPage, 237);
        expect(visits, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        paging.dispose();
      });
    }
  }
}
