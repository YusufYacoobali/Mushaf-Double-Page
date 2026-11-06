import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

void main() {
  late Directory dir;
  late String image;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('adaptive_quran_');
    image = '${dir.path}/page.png';
    await File(image).writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4'
        '2mP8/x8AAusB9Wl2nkwAAAAASUVORK5CYII=',
      ),
    );
  });
  tearDownAll(() async => dir.delete(recursive: true));
  for (final mushaf in ['indopak_tajweed', 'madani']) {
    testWidgets(
      '$mushaf compact 80 percent page stays near full width when the dock toggles',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final paging = ReaderPaging(
          initialPage: 237,
          lastPage: mushaf == 'madani' ? 624 : 851,
        );
        final visits = <int>[];
        var expanded = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppPalette.emerald.toThemeData(),
            home: StatefulBuilder(
              builder: (context, refresh) => Scaffold(
                body: LayoutBuilder(
                  builder: (context, constraints) {
                    final layout = ReaderLayout.resolve(
                      size: constraints.biggest,
                      pageAspectRatio: QuranPageView.aspectRatioForMushaf(
                        mushaf,
                      ),
                    );
                    return Stack(
                      children: [
                        AdaptiveQuranPages(
                          paging: paging,
                          layout: layout,
                          singleScale: .8,
                          spreadScale: .7,
                          imagePath: (_) => image,
                          isDarkMode: false,
                          aspectRatio: QuranPageView.aspectRatioForMushaf(
                            mushaf,
                          ),
                          highlightFor: (_) => const [
                            Rect.fromLTWH(.2, .3, .4, .05),
                          ],
                          highlightColor: Colors.amber,
                          onPageChanged: visits.add,
                          onFocus: (_) {},
                        ),
                        Positioned.fromRect(
                          rect: layout.controlsRegion,
                          child: Stack(
                            children: [
                              ReaderDock(
                                placement: layout.dockPlacement,
                                expanded: expanded,
                                onToggle: () =>
                                    refresh(() => expanded = !expanded),
                                palette: AppPalette.emerald,
                                zoom: ReaderZoom(
                                  portrait: true,
                                  palette: AppPalette.emerald,
                                  scale: .8,
                                  minimum: .7,
                                  onDecrease: () {},
                                  onIncrease: () {},
                                ),
                                actions: [
                                  for (var i = 0; i < 5; i++)
                                    IconButton(
                                      tooltip: 'Action $i',
                                      onPressed: () {},
                                      icon: const Icon(Icons.book),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final page = find.byKey(const ValueKey('quran-page-237'));
        final collapsed = tester.getRect(page);
        expect(collapsed.width, inInclusiveRange(304, 320));
        expect(
          collapsed.width / collapsed.height,
          closeTo(QuranPageView.aspectRatioForMushaf(mushaf), .001),
        );
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
        expect(tester.getRect(page), collapsed);
        await tester.tap(find.byTooltip('Collapse navigation'));
        await tester.pumpAndSettle();
        expect(tester.getRect(page), collapsed);
        expect(paging.focusedPage, 237);
        expect(visits, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        paging.dispose();
      },
    );
    testWidgets(
      '$mushaf folds and resizes without a page visit or stale callback, preserving focused page and selection',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final paging = ReaderPaging(
          initialPage: 237,
          lastPage: mushaf == 'madani' ? 624 : 851,
        );
        final visits = <int>[], focused = <int>[];
        const highlight = [Rect.fromLTWH(.2, .3, .4, .05)];
        ReaderLayout? layout;
        Widget host() => MaterialApp(
          theme: AppPalette.emerald.toThemeData(),
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                layout = ReaderLayout.resolve(
                  size: constraints.biggest,
                  pageAspectRatio: QuranPageView.aspectRatioForMushaf(mushaf),
                );
                return AdaptiveQuranPages(
                  paging: paging,
                  layout: layout!,
                  singleScale: .8,
                  spreadScale: .7,
                  imagePath: (_) => image,
                  isDarkMode: false,
                  aspectRatio: QuranPageView.aspectRatioForMushaf(mushaf),
                  highlightFor: (p) => p == 237 ? highlight : [],
                  highlightColor: Colors.amber,
                  onPageChanged: visits.add,
                  onFocus: focused.add,
                );
              },
            ),
          ),
        );
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        expect(paging.visiblePages, [237]);
        expect(visits, isEmpty);
        final oldView = tester.widget<PageView>(find.byType(PageView));
        tester.view.physicalSize = const Size(900, 900);
        await tester.pumpAndSettle();
        expect(layout!.singlePage, isFalse);
        expect(layout!.spreadLayout, ReaderSpreadLayout.widePortrait);
        expect(layout!.bottomDock, isTrue);
        expect(paging.focusedPage, 237);
        expect(paging.visiblePages, [236, 237]);
        expect(visits, isEmpty);
        oldView.onPageChanged!(0);
        expect(paging.focusedPage, 237);
        expect(visits, isEmpty);
        final right = tester.getRect(
          find.byKey(const ValueKey('quran-page-236')),
        );
        final left = tester.getRect(
          find.byKey(const ValueKey('quran-page-237')),
        );
        expect(right.center.dx, greaterThan(left.center.dx));
        expect(
          right.width / right.height,
          closeTo(QuranPageView.aspectRatioForMushaf(mushaf), .001),
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('quran-page-237')),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('quran-page-236')),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
        );
        await tester.tapAt(left.center);
        await tester.pump();
        tester.view.physicalSize = const Size(320, 568);
        await tester.pumpAndSettle();
        expect(paging.visiblePages, [237]);
        expect(visits, isEmpty);
        tester.view.physicalSize = const Size(844, 390);
        await tester.pumpAndSettle();
        expect(paging.singlePage, isFalse);
        await tester.tapAt(
          tester.getCenter(find.byKey(const ValueKey('quran-page-236'))),
        );
        await tester.pump();
        expect(paging.focusedPage, 236);
        expect(focused, [236]);
        tester.view.physicalSize = const Size(340, 700);
        await tester.pumpAndSettle();
        expect(paging.visiblePages, [236]);
        expect(visits, isEmpty);
        await tester.drag(find.byType(PageView), const Offset(300, 0));
        await tester.pumpAndSettle();
        expect(paging.focusedPage, 237);
        expect(visits, [237]);
        // Even a late callback from the old spread cannot persist a distant page.
        oldView.onPageChanged!(400);
        expect(paging.focusedPage, 237);
        expect(visits, [237]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        paging.dispose();
      },
    );
  }
  testWidgets(
    'hinge split preserves RTL pages, normalized tap coordinates and reachable controls',
    (tester) async {
      tester.view.physicalSize = const Size(950, 669);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const hinge = Rect.fromLTWH(460, 0, 30, 669);
      final layout = ReaderLayout.resolve(
        size: const Size(950, 669),
        displayFeatures: const [
          DisplayFeature(
            bounds: hinge,
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      );
      final paging = ReaderPaging(initialPage: 237, lastPage: 624);
      final taps = <(int, double, double)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPalette.emerald.toThemeData(),
          home: Scaffold(
            body: Stack(
              children: [
                AdaptiveQuranPages(
                  paging: paging,
                  layout: layout,
                  singleScale: .8,
                  spreadScale: .7,
                  imagePath: (_) => image,
                  isDarkMode: true,
                  aspectRatio: QuranPageView.madaniPageAspectRatio,
                  highlightFor: (_) => const [Rect.fromLTWH(.2, .3, .4, .05)],
                  highlightColor: Colors.amber,
                  onPageChanged: (_) {},
                  onFocus: (_) {},
                  onTap: (p, x, y) => taps.add((p, x, y)),
                ),
                Positioned.fromRect(
                  rect: layout.controlsRegion,
                  child: Stack(
                    children: [
                      ReaderDock(
                        placement: layout.dockPlacement,
                        expanded: true,
                        onToggle: () {},
                        palette: AppPalette.emerald,
                        zoom: const SizedBox(width: 96),
                        actions: [
                          for (var i = 0; i < 5; i++)
                            IconButton(
                              tooltip: 'Action $i',
                              onPressed: () {},
                              icon: const Icon(Icons.book),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(layout.spreadLayout, ReaderSpreadLayout.separateRegions);
      expect(
        find.descendant(
          of: find.byType(AdaptiveQuranPages),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNWidgets(2),
      );
      for (final page in [236, 237]) {
        final rect = tester.getRect(find.byKey(ValueKey('quran-page-$page')));
        expect(rect.overlaps(hinge), isFalse);
        expect(
          rect.width / rect.height,
          closeTo(QuranPageView.madaniPageAspectRatio, .001),
        );
        await tester.tapAt(
          Offset(rect.left + rect.width * .25, rect.top + rect.height * .35),
        );
        await tester.pump();
        expect(taps.last.$1, page);
        expect(taps.last.$2, closeTo(.25, .001));
        expect(taps.last.$3, closeTo(.35, .001));
      }
      for (var i = 0; i < 5; i++) {
        final button = find.byTooltip('Action $i');
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getRect(button).overlaps(hinge), isFalse);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
    },
  );
  testWidgets(
    'rapid resizing during animated navigation rejects retired controllers',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final paging = ReaderPaging(initialPage: 237, lastPage: 851);
      final visits = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (_, constraints) => AdaptiveQuranPages(
                paging: paging,
                layout: ReaderLayout.resolve(size: constraints.biggest),
                singleScale: .8,
                spreadScale: .7,
                imagePath: (_) => image,
                isDarkMode: false,
                aspectRatio: QuranPageView.pageAspectRatio,
                highlightFor: (_) => [],
                highlightColor: Colors.amber,
                onPageChanged: visits.add,
                onFocus: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final navigation = paging.goTo(600, animate: true);
      await tester.pump(const Duration(milliseconds: 50));
      for (final size in [
        const Size(900, 900),
        const Size(340, 700),
        const Size(1200, 800),
        const Size(390, 844),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await navigation;
      expect(paging.focusedPage, 600);
      expect(paging.visiblePages, [600]);
      expect(visits, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
    },
  );
}
