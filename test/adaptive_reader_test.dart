import 'dart:ui' as ui;
import 'dart:io';
import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/components/quran_page_turn_painter.dart';
import 'package:mushaf_two_page/components/quran_page_turn_view.dart';
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
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final page = await picture.toImage(721, 1058);
    final bytes = await page.toByteData(format: ui.ImageByteFormat.png);
    await File(image).writeAsBytes(bytes!.buffer.asUint8List());
    page.dispose();
    picture.dispose();
  });
  tearDownAll(() async => dir.delete(recursive: true));
  testWidgets(
    'accessibility scroll actions turn RTL and stop at each boundary',
    (tester) async {
      const size = Size(390, 844);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final paging = ReaderPaging(initialPage: 1, lastPage: 2);
      final visits = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveQuranPages(
            paging: paging,
            layout: ReaderLayout.resolve(size: size),
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
      );
      await tester.pumpAndSettle();
      const forward = ui.SemanticsAction.scrollRight;
      const back = ui.SemanticsAction.scrollLeft;
      for (final (action, unavailable, target) in [
        (forward, back, 2),
        (back, forward, 1),
      ]) {
        expect(find.semantics.byAction(unavailable), findsNothing);
        final node = find.semantics.byAction(action).evaluate().single;
        node.owner!.performAction(node.id, action);
        await tester.pumpAndSettle();
        expect(paging.visiblePages, [target]);
      }
      expect(find.semantics.byAction(back), findsNothing);
      expect(visits, [2, 1]);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      paging.dispose();
    },
  );

  for (final missing in [const RawImage(), const Placeholder()]) {
    testWidgets(
      'an unavailable ${missing.runtimeType} turn target recovers on the next decoded page',
      (tester) async {
        const size = Size(400, 800);
        final layout = ReaderLayout.resolve(size: size);
        final paging = ReaderPaging(initialPage: 1, lastPage: 3)
          ..configure(layout.pageMode);
        final loading = ValueNotifier(true);
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.white, BlendMode.src);
        final picture = recorder.endRecording();
        final image = picture.toImageSync(8, 8);
        picture.dispose();
        final visits = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: QuranPageTurnView(
              paging: paging,
              layout: layout,
              layoutIdentity: size,
              isDarkMode: false,
              onPageChanged: visits.add,
              buildSurface: (index, active, wrapLeaf) =>
                  ValueListenableBuilder<bool>(
                    valueListenable: loading,
                    builder: (context, pending, _) => Center(
                      child: wrapLeaf(
                        index + 1,
                        SizedBox(
                          width: 200,
                          height: 300,
                          child: index == 1 && pending
                              ? missing
                              : RawImage(image: image),
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        );
        final painter = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is QuranPageTurnPainter,
        );
        final cold = paging.goTo(2, animate: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(painter, findsNothing);
        expect(paging.focusedPage, 1);
        await tester.pumpAndSettle();
        expect(await cold, isTrue);
        expect(paging.focusedPage, 2);
        loading.value = false;
        await tester.pumpAndSettle();
        final warm = paging.goTo(3, animate: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 85));
        expect(painter, findsOneWidget);
        expect(paging.progress, greaterThan(0));
        await tester.pumpAndSettle();
        expect(await warm, isTrue);
        expect(paging.focusedPage, 3);
        expect(visits, isEmpty);
        await tester.pumpWidget(const SizedBox());
        paging.dispose();
        loading.dispose();
        image.dispose();
      },
    );
  }

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
        expect(collapsed.width, 320);
        expect(collapsed.height, closeTo(568 * .8, .001));
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
        final drag = await tester.startGesture(const Offset(80, 350));
        await drag.moveBy(const Offset(60, 0));
        await tester.pump();
        expect(paging.settled, isFalse);
        final staleOperation = paging.operation;
        tester.view.physicalSize = const Size(900, 900);
        await tester.pumpAndSettle();
        expect(layout!.singlePage, isFalse);
        expect(layout!.spreadLayout, ReaderSpreadLayout.widePortrait);
        expect(layout!.bottomDock, isTrue);
        expect(paging.focusedPage, 237);
        expect(paging.visiblePages, [236, 237]);
        expect(visits, isEmpty);
        await drag.up();
        await tester.pumpAndSettle();
        expect(paging.completeTurn(staleOperation), isFalse);
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
        await tester.dragFrom(const Offset(20, 300), const Offset(280, 0));
        await tester.pumpAndSettle();
        expect(paging.focusedPage, 237);
        expect(visits, [237]);
        // Late animation completion cannot overwrite the newer visit.
        expect(paging.completeTurn(staleOperation), isFalse);
        expect(paging.focusedPage, 237);
        expect(visits, [237]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        paging.dispose();
      },
    );
  }
  testWidgets(
    'book hinge shows current then next page, with safe taps and controls',
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
                        zoom: const SizedBox(width: 40, height: 80),
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
        findsNothing,
      );
      expect(layout.pageMode, ReaderPageMode.dualScreenBook);
      expect(paging.visiblePages, [237, 238]);
      expect(
        tester.getRect(find.byKey(const ValueKey('quran-page-237'))).left,
        greaterThanOrEqualTo(hinge.right),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('quran-page-238'))).right,
        lessThanOrEqualTo(hinge.left),
      );
      for (final page in [237, 238]) {
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
    'rapid resizing during an adjacent turn preserves the exact command target',
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
      final navigation = paging.goTo(238, animate: true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(paging.settled, isFalse);
      expect(paging.focusedPage, 237);
      final staleOperation = paging.operation;
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
      expect(await navigation, isTrue);
      expect(paging.focusedPage, 238);
      expect(paging.visiblePages, [238]);
      expect(paging.completeTurn(staleOperation), isFalse);
      expect(visits, isEmpty);

      await paging.goTo(600, animate: true);
      expect(paging.settled, isTrue);
      await tester.pumpAndSettle();
      expect(paging.focusedPage, 600);
      expect(paging.visiblePages, [600]);
      expect(visits, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
    },
  );
}
