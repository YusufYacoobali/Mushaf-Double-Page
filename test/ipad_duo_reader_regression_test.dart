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
  // iPad mini 6: 744 x 1133 logical points. Other iPads and square
  // multitasking windows must also keep the original portrait reader.
  for (final edition in ['indopak_tajweed', 'madani']) {
    for (final size in [
      const Size(744, 1133),
      const Size(768, 1024),
      const Size(820, 1180),
      const Size(834, 1194),
      const Size(1024, 1366),
      const Size(900, 900),
    ]) {
      test('$edition iPad portrait at $size preserves the v4 full page', () {
        final layout = ReaderLayout.resolve(
          size: size,
          padding: const EdgeInsets.only(top: 24, bottom: 20),
          preserveLegacyIPadPortrait: true,
          pageAspectRatio: QuranPageView.aspectRatioForMushaf(edition),
        );
        expect(layout.pageMode, ReaderPageMode.single);
        expect(layout.dockPlacement, DockPlacement.bottom);
        expect(layout.fullWidthPortrait, isTrue);
        expect(layout.pageRegions.single, Offset.zero & size);
        expect(layout.usableContentBounds, Offset.zero & size);
      });
    }

    test('$edition iPad mini landscape retains a facing-page spread', () {
      final layout = ReaderLayout.resolve(
        size: const Size(1133, 744),
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 20),
        preserveLegacyIPadPortrait: true,
        pageAspectRatio: QuranPageView.aspectRatioForMushaf(edition),
      );
      expect(layout.pageMode, ReaderPageMode.spread);
      expect(layout.spreadLayout, ReaderSpreadLayout.centeredLandscape);
      expect(layout.dockPlacement, DockPlacement.side);
    });

    test('$edition unfolded Duo 669x951 portrait shows one centered page', () {
      // Measured from the iPhone Duo Xcode 27 simulator, not an assumed size.
      final layout = ReaderLayout.resolve(
        size: const Size(669, 951),
        padding: const EdgeInsets.only(top: 24, bottom: 21),
        iosPhoneWidePortrait: true,
        pageAspectRatio: QuranPageView.aspectRatioForMushaf(edition),
      );
      expect(layout.pageMode, ReaderPageMode.single);
      expect(layout.spreadLayout, ReaderSpreadLayout.widePortrait);
      expect(layout.pageRegions.length, 1);
      expect(layout.fullWidthPortrait, isFalse);
      expect(layout.dockPlacement, DockPlacement.bottom);
    });

    test('$edition Duo folded 466x678 remains single page', () {
      final layout = ReaderLayout.resolve(
        size: const Size(466, 678),
        iosPhoneWidePortrait: true,
        pageAspectRatio: QuranPageView.aspectRatioForMushaf(edition),
      );
      expect(layout.pageMode, ReaderPageMode.single);
      expect(layout.fullWidthPortrait, isTrue);
    });

    test('$edition Android 669x951 portrait retains original width policy', () {
      final layout = ReaderLayout.resolve(
        size: const Size(669, 951),
        pageAspectRatio: QuranPageView.aspectRatioForMushaf(edition),
      );
      expect(layout.pageMode, ReaderPageMode.single);
    });
  }

  late Directory images;
  late String imagePath;
  setUpAll(() async {
    images = await Directory.systemTemp.createTemp('ipad_layout_regression_');
    imagePath = '${images.path}/page.png';
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final sample = await picture.toImage(64, 96);
    final bytes = await sample.toByteData(format: ui.ImageByteFormat.png);
    await File(imagePath).writeAsBytes(bytes!.buffer.asUint8List());
    sample.dispose();
    picture.dispose();
  });
  tearDownAll(() async => images.delete(recursive: true));

  for (final edition in ['indopak_tajweed', 'madani']) {
    testWidgets(
      '$edition iPad mini portrait-landscape-portrait keeps exact page and geometry',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(744, 1133);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);

        final paging = ReaderPaging(
          initialPage: 237,
          lastPage: edition == 'madani' ? 624 : 851,
        );
        addTearDown(paging.dispose);
        final visits = <int>[];
        late ReaderLayout layout;
        var expanded = false;
        late StateSetter refresh;
        Widget host() => MaterialApp(
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
                      preserveLegacyIPadPortrait: true,
                      pageAspectRatio: QuranPageView.aspectRatioForMushaf(
                        edition,
                      ),
                    );
                    return Stack(
                      children: [
                        AdaptiveQuranPages(
                          paging: paging,
                          layout: layout,
                          singleScale: .8,
                          spreadScale: .7,
                          imagePath: (_) => imagePath,
                          isDarkMode: false,
                          aspectRatio: QuranPageView.aspectRatioForMushaf(
                            edition,
                          ),
                          highlightFor: (_) => const [],
                          highlightColor: Colors.amber,
                          onPageChanged: visits.add,
                          onFocus: (_) {},
                        ),
                        ReaderDockOverlay(
                          layout: layout,
                          child: ReaderDock(
                            placement: layout.dockPlacement,
                            expanded: expanded,
                            onToggle: () => refresh(() => expanded = !expanded),
                            palette: AppPalette.emerald,
                            zoom: ReaderZoom(
                              portrait: layout.bottomDock,
                              palette: AppPalette.emerald,
                              scale: .8,
                              minimum: .7,
                              onDecrease: () {},
                              onIncrease: () {},
                            ),
                            actions: [
                              IconButton(
                                tooltip: 'Bookmarks',
                                icon: const Icon(Icons.bookmark),
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        );

        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        expect(layout.pageMode, ReaderPageMode.single);
        expect(paging.visiblePages, [237]);
        final portrait = tester.getRect(
          find.byKey(const ValueKey('quran-page-237')),
        );
        expect(portrait.width, closeTo(744, .001));
        expect(portrait.height, closeTo(1133 * .8, .001));
        expect(portrait.top, closeTo((1133 - 1133 * .8) / 2, .001));
        expect(find.byTooltip('Open navigation'), findsOneWidget);
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('quran-page-237'))),
          portrait,
        );

        tester.view.physicalSize = const Size(1133, 744);
        await tester.pumpAndSettle();
        expect(layout.pageMode, ReaderPageMode.spread);
        expect(paging.visiblePages, [236, 237]);
        final left = tester.getRect(
          find.byKey(const ValueKey('quran-page-237')),
        );
        final right = tester.getRect(
          find.byKey(const ValueKey('quran-page-236')),
        );
        expect(right.center.dx, greaterThan(left.center.dx));
        expect(visits, isEmpty);

        // Focusing either leaf of the facing-page spread must survive rotation.
        await tester.tapAt(right.center);
        await tester.pump();
        expect(paging.focusedPage, 236);
        tester.view.physicalSize = const Size(744, 1133);
        await tester.pumpAndSettle();
        expect(layout.pageMode, ReaderPageMode.single);
        expect(paging.visiblePages, [236]);
        expect(
          tester.getRect(find.byKey(const ValueKey('quran-page-236'))).width,
          closeTo(744, .001),
        );
        expect(visits, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
