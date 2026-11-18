import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/audio_vertical_follower.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

void main() {
  late Directory directory;
  late String image;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('vertical_follow_');
    image = '${directory.path}/page.png';
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final page = await picture.toImage(72, 106);
    final bytes = await page.toByteData(format: ui.ImageByteFormat.png);
    await File(image).writeAsBytes(bytes!.buffer.asUint8List());
    page.dispose();
    picture.dispose();
  });
  tearDownAll(() => directory.delete(recursive: true));

  void size(WidgetTester tester, Size value) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  AudioVerticalFollower follower(int page) => AudioVerticalFollower(
    rectsFor: (p, s, a, m) => p == page
        ? switch (a) {
            1 => const [Rect.fromLTWH(.1, .88, .8, .05)],
            2 => const [Rect.fromLTWH(.1, .02, .8, .05)],
            _ => const [
              Rect.fromLTWH(.1, .4, .8, .05),
              Rect.fromLTWH(.1, .95, .8, .04),
            ],
          }
        : [],
  );
  void follow(
    AudioVerticalFollower follower,
    int ayah, {
    String mushaf = 'madani',
  }) {
    final request = follower.beginAyah(
      playing: true,
      visible: true,
      session: 1,
      cycle: 1,
      surah: 2,
      ayah: ayah,
      mushaf: mushaf,
    );
    if (request != null) follower.reveal(request);
  }

  List<ScrollController> scrolls(WidgetTester tester) => tester
      .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
      .map((w) => w.controller!)
      .toList();

  for (final edition in ['madani', 'indopak_tajweed']) {
    testWidgets(
      '$edition landscape moves only enough in each direction and leaves visible ayahs still',
      (tester) async {
        size(tester, const Size(800, 400));
        final f = follower(4)
          ..configureView(layoutIdentity: 'landscape', visiblePages: [4, 5]);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuranPageView.doublePage(
                spreadIndex: 2,
                totalPages: 20,
                pageScale: 1,
                imagePath: (_) => image,
                aspectRatio: QuranPageView.aspectRatioForMushaf(edition),
                isDarkMode: false,
                verticalFollower: f,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = scrolls(tester).single;
        final page = tester.getRect(find.byKey(const ValueKey('quran-page-4')));
        final expected = page.top + page.height * .93 - 400 + 16;
        follow(f, 1, mushaf: edition);
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(expected, .01));
        final before = scroll.offset;
        for (var tick = 0; tick < 20; tick++) {
          follow(f, 1, mushaf: edition);
        }
        await tester.pumpAndSettle();
        expect(scroll.offset, before);
        follow(f, 3, mushaf: edition);
        await tester.pumpAndSettle();
        expect(
          scroll.offset,
          before,
        ); // One of the ayah's lines is already visible.
        follow(f, 2, mushaf: edition);
        await tester.pumpAndSettle();
        expect(
          scroll.offset,
          closeTo(0, .01),
        ); // Extent clamps the upper target.
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
    testWidgets(
      '$edition portrait reveals with exactly the same zoom and horizontal translation',
      (tester) async {
        size(tester, const Size(400, 800));
        final f = follower(4)
          ..configureView(layoutIdentity: 'portrait', visiblePages: [4]);
        final transform = TransformationController(
          Matrix4.identity()
            ..setEntry(0, 0, 1.4)
            ..setEntry(1, 1, 1.4)
            ..setEntry(0, 3, -35),
        );
        final taps = <(double, double)>[];
        var backgroundTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuranPageView.singlePage(
                logicalPage: 4,
                pageScale: .7,
                imagePath: (_) => image,
                aspectRatio: QuranPageView.aspectRatioForMushaf(edition),
                isDarkMode: false,
                transformationController: transform,
                verticalFollower: f,
                onTap: (_, x, y) => taps.add((x, y)),
                onBackgroundTap: () => backgroundTaps++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final original = List<double>.of(transform.value.storage);
        follow(f, 1, mushaf: edition);
        await tester.pumpAndSettle();
        expect(transform.value.storage[13], lessThan(0));
        for (var i = 0; i < 16; i++) {
          if (i != 13) expect(transform.value.storage[i], original[i]);
        }
        final frame = tester.getRect(
          find.byKey(const ValueKey('quran-page-4')),
        );
        expect(frame.top + frame.height * .93, closeTo(784, .02));
        await tester.tapAt(
          Offset(frame.left + frame.width * .5, frame.top + frame.height * .9),
        );
        await tester.pump();
        expect(taps.single.$1, closeTo(.5, .001));
        expect(taps.single.$2, closeTo(.9, .001));
        expect(backgroundTaps, 0);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
        transform.dispose();
      },
    );
  }
  for (final page in [4, 5]) {
    testWidgets('separate landscape regions move only page $page', (
      tester,
    ) async {
      size(tester, const Size(800, 400));
      final f = follower(page)
        ..configureView(layoutIdentity: 'separate', visiblePages: [4, 5]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranPageView.doublePage(
              spreadIndex: 2,
              totalPages: 20,
              pageScale: 1,
              imagePath: (_) => image,
              isDarkMode: false,
              verticalFollower: f,
              pageRegions: const [
                Rect.fromLTWH(20, 20, 350, 330),
                Rect.fromLTWH(430, 20, 350, 330),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controllers = scrolls(tester);
      follow(f, 1);
      await tester.pumpAndSettle();
      expect(controllers[page == 5 ? 0 : 1].offset, greaterThan(0));
      expect(controllers[page == 5 ? 1 : 0].offset, 0);
      final frame = tester.getRect(find.byKey(ValueKey('quran-page-$page')));
      expect(frame.top + frame.height * .93, closeTo(334, .02));
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    });
  }
  testWidgets('an entirely visible portrait or landscape page never moves', (
    tester,
  ) async {
    final f = follower(4)
      ..configureView(layoutIdentity: 'fit', visiblePages: [4, 5]);
    size(tester, const Size(800, 400));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuranPageView.doublePage(
            spreadIndex: 2,
            totalPages: 20,
            pageScale: .6,
            imagePath: (_) => image,
            isDarkMode: false,
            verticalFollower: f,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    follow(f, 1);
    await tester.pumpAndSettle();
    expect(scrolls(tester).single.offset, 0);
    await tester.pumpWidget(const SizedBox());
    f.configureView(layoutIdentity: 'fit-portrait', visiblePages: [4]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuranPageView.singlePage(
            logicalPage: 4,
            pageScale: .8,
            imagePath: (_) => image,
            isDarkMode: false,
            verticalFollower: f,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    follow(f, 2);
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.transformationController!.value, Matrix4.identity());
    expect(viewer.panEnabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });
  testWidgets(
    'manual drag cancels an animation and position ticks never pull it back',
    (tester) async {
      size(tester, const Size(800, 400));
      final f = follower(4)
        ..configureView(layoutIdentity: 'landscape', visiblePages: [4, 5]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranPageView.doublePage(
              spreadIndex: 2,
              totalPages: 20,
              pageScale: 1,
              imagePath: (_) => image,
              isDarkMode: false,
              verticalFollower: f,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      follow(f, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final scroll = scrolls(tester).single;
      final pointer = await tester.startGesture(const Offset(600, 200));
      final stopped = scroll.offset;
      await tester.pump(const Duration(milliseconds: 300));
      expect(scroll.offset, stopped);
      await pointer.moveBy(const Offset(0, 30));
      await pointer.up();
      await tester.pumpAndSettle();
      final manual = scroll.offset;
      follow(f, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, manual);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
  testWidgets(
    'portrait vertical panning still lets horizontal swipes turn pages',
    (tester) async {
      size(tester, const Size(400, 800));
      final controllers = List.generate(
        3,
        (_) => TransformationController(
          Matrix4.identity()
            ..setEntry(0, 0, 1.4)
            ..setEntry(1, 1, 1.4),
        ),
      );
      var page = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView.builder(
              reverse: true,
              itemCount: 3,
              onPageChanged: (value) => page = value,
              itemBuilder: (_, index) => QuranPageView.singlePage(
                logicalPage: index,
                pageScale: .7,
                imagePath: (_) => image,
                isDarkMode: false,
                transformationController: controllers[index],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
            .panEnabled,
        isTrue,
      );
      await tester.timedDragFrom(
        const Offset(200, 400),
        const Offset(0, -70),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();
      expect(controllers[0].value.storage[13], lessThan(0));
      expect(page, 0);
      await tester.dragFrom(const Offset(60, 400), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(page, 1);
      await tester.pumpWidget(const SizedBox());
      for (final controller in controllers) {
        controller.dispose();
      }
    },
  );
  testWidgets(
    'reduced motion reveals immediately and parent rebuilds do not cancel normal animations',
    (tester) async {
      size(tester, const Size(800, 400));
      final f = follower(4)
        ..configureView(layoutIdentity: 'landscape', visiblePages: [4, 5]);
      late StateSetter refresh;
      var reduced = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) {
              refresh = update;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: Scaffold(
                  body: QuranPageView.doublePage(
                    spreadIndex: 2,
                    totalPages: 20,
                    pageScale: 1,
                    imagePath: (_) => image,
                    isDarkMode: false,
                    verticalFollower: f,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = scrolls(tester).single;
      follow(f, 1);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        refresh(() {});
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(scroll.offset, greaterThan(120));
      refresh(() => reduced = true);
      await tester.pumpAndSettle();
      follow(f, 2);
      await tester.pump();
      expect(scroll.offset, 0);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
  testWidgets(
    'adaptive navigation lays out the target before revealing and rotation cancels stale work',
    (tester) async {
      size(tester, const Size(800, 400));
      final f = follower(8);
      final paging = ReaderPaging(initialPage: 4, lastPage: 30);
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) {
              refresh = update;
              return Scaffold(
                body: LayoutBuilder(
                  builder: (context, bounds) => AdaptiveQuranPages(
                    paging: paging,
                    layout: ReaderLayout.resolve(size: bounds.biggest),
                    singleScale: .7,
                    spreadScale: 1,
                    imagePath: (_) => image,
                    isDarkMode: false,
                    aspectRatio: QuranPageView.pageAspectRatio,
                    highlightFor: (_) => [],
                    highlightColor: Colors.amber,
                    verticalFollower: f,
                    onPageChanged: (_) => refresh(() {}),
                    onFocus: (_) {},
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final request = f.beginAyah(
        playing: true,
        visible: true,
        session: 1,
        cycle: 1,
        surah: 2,
        ayah: 1,
        mushaf: 'madani',
      )!;
      final navigating = paging.goTo(8, animate: true);
      refresh(() {});
      final done = f.revealAfterNavigation(request, navigating);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scrolls(tester).every((s) => s.offset == 0), isTrue);
      await tester.pumpAndSettle();
      await done;
      expect(paging.visiblePages, [8, 9]);
      expect(scrolls(tester).any((s) => s.offset > 0), isTrue);
      final pending = f.beginAyah(
        playing: true,
        visible: true,
        session: 1,
        cycle: 1,
        surah: 2,
        ayah: 2,
        mushaf: 'madani',
      )!;
      final nextNavigation = paging.goTo(12, animate: true);
      refresh(() {});
      final cancelled = f.revealAfterNavigation(pending, nextNavigation);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      await cancelled;
      expect(paging.focusedPage, 12);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      paging.dispose();
    },
  );
  testWidgets('a rapid ayah change cancels the old vertical animation', (
    tester,
  ) async {
    size(tester, const Size(800, 400));
    final f = follower(4)
      ..configureView(layoutIdentity: 'landscape', visiblePages: [4, 5]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuranPageView.doublePage(
            spreadIndex: 2,
            totalPages: 20,
            pageScale: 1,
            imagePath: (_) => image,
            isDarkMode: false,
            verticalFollower: f,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    follow(f, 1);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(scrolls(tester).single.offset, greaterThan(0));
    follow(f, 2);
    await tester.pumpAndSettle();
    expect(scrolls(tester).single.offset, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(scrolls(tester).single.offset, 0);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });
  testWidgets(
    'portrait reveal uses safe insets and actual bottom controls without changing scale',
    (tester) async {
      size(tester, const Size(400, 800));
      final f = AudioVerticalFollower(
        rectsFor: (p, s, a, m) => [
          Rect.fromLTWH(.1, a == 1 ? .02 : .9, .8, .04),
        ],
        obstructions: () => const [Rect.fromLTWH(0, 680, 400, 120)],
      )..configureView(layoutIdentity: 'safe-portrait', visiblePages: [4]);
      final transform = TransformationController();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              padding: EdgeInsets.only(top: 59, bottom: 34),
            ),
            child: Scaffold(
              body: QuranPageView.singlePage(
                logicalPage: 4,
                pageScale: 1,
                imagePath: (_) => image,
                isDarkMode: false,
                transformationController: transform,
                verticalFollower: f,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      follow(f, 1);
      await tester.pumpAndSettle();
      var frame = tester.getRect(find.byKey(const ValueKey('quran-page-4')));
      expect(frame.top + frame.height * .02, closeTo(75, .02));
      follow(f, 2);
      await tester.pumpAndSettle();
      frame = tester.getRect(find.byKey(const ValueKey('quran-page-4')));
      expect(frame.top + frame.height * .94, closeTo(660, .02));
      expect(transform.value.getMaxScaleOnAxis(), 1);
      expect(transform.value.storage[12], 0);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      transform.dispose();
    },
  );
  testWidgets('foldable follower uses the page region above its dock gutter', (
    tester,
  ) async {
    size(tester, const Size(950, 669));
    final f = follower(4);
    final paging = ReaderPaging(initialPage: 4, lastPage: 30);
    final layout = ReaderLayout.resolve(
      size: const Size(950, 669),
      displayFeatures: const [
        ui.DisplayFeature(
          bounds: Rect.fromLTWH(460, 0, 30, 669),
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveQuranPages(
            paging: paging,
            layout: layout,
            singleScale: .8,
            spreadScale: 1,
            imagePath: (_) => image,
            isDarkMode: false,
            aspectRatio: QuranPageView.pageAspectRatio,
            highlightFor: (_) => [],
            highlightColor: Colors.amber,
            verticalFollower: f,
            onPageChanged: (_) {},
            onFocus: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    follow(f, 1);
    await tester.pumpAndSettle();
    final controllers = scrolls(tester);
    expect(controllers[0].offset, greaterThan(0));
    expect(controllers[1].offset, 0);
    final frame = tester.getRect(find.byKey(const ValueKey('quran-page-4')));
    expect(
      frame.top + frame.height * .93,
      closeTo(layout.pageRegions[0].bottom - 16, .02),
    );
    await tester.pumpWidget(const SizedBox());
    f.dispose();
    paging.dispose();
  });
}
