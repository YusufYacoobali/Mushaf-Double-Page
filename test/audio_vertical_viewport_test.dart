import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/audio_vertical_viewport.dart';
import 'package:mushaf_two_page/components/quran_page_turn_view.dart';
import 'package:mushaf_two_page/components/reader_audio_controls.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
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

  Rect paintedRect(WidgetTester tester, int page, Rect normalized) {
    final frame = tester.getRect(find.byKey(ValueKey('quran-page-$page')));
    return Rect.fromLTRB(
      frame.left + frame.width * normalized.left,
      frame.top + frame.height * normalized.top,
      frame.left + frame.width * normalized.right,
      frame.top + frame.height * normalized.bottom,
    );
  }

  void expectFullyVisible(Rect rect, {double top = 0, double bottom = 400}) {
    expect(rect.top, greaterThanOrEqualTo(top - .02));
    expect(rect.bottom, lessThanOrEqualTo(bottom + .02));
  }

  for (final edition in ['madani', 'indopak_tajweed']) {
    testWidgets(
      '$edition landscape reveals complete ayahs in each direction without following position ticks',
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
        follow(f, 1, mushaf: edition);
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        expectFullyVisible(
          paintedRect(tester, 4, const Rect.fromLTWH(.1, .88, .8, .05)),
        );
        final before = scroll.offset;
        for (var tick = 0; tick < 20; tick++) {
          follow(f, 1, mushaf: edition);
        }
        await tester.pumpAndSettle();
        expect(scroll.offset, before);
        follow(f, 3, mushaf: edition);
        await tester.pumpAndSettle();
        for (final line in const [
          Rect.fromLTWH(.1, .4, .8, .05),
          Rect.fromLTWH(.1, .95, .8, .04),
        ]) {
          expectFullyVisible(paintedRect(tester, 4, line));
        }
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
      '$edition shows every line when a multiline ayah is partly above or below the screen',
      (tester) async {
        size(tester, const Size(800, 400));
        const lower = [
          Rect.fromLTWH(.1, .6, .8, .04),
          Rect.fromLTWH(.1, .68, .8, .04),
          Rect.fromLTWH(.1, .76, .8, .04),
        ];
        const upper = [
          Rect.fromLTWH(.1, .2, .8, .04),
          Rect.fromLTWH(.1, .28, .8, .04),
          Rect.fromLTWH(.1, .36, .8, .04),
        ];
        final f = AudioVerticalFollower(
          rectsFor: (page, surah, ayah, mushaf) =>
              page == 4 ? (ayah == 1 ? lower : upper) : [],
        )..configureView(layoutIdentity: 'multiline', visiblePages: [4, 5]);
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
        expectFullyVisible(paintedRect(tester, 4, lower.first));
        expect(paintedRect(tester, 4, lower.last).bottom, greaterThan(400));
        follow(f, 1, mushaf: edition);
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        for (final line in lower) {
          expectFullyVisible(
            paintedRect(tester, 4, line),
            top: 16,
            bottom: 384,
          );
        }

        expect(paintedRect(tester, 4, upper.first).top, lessThan(0));
        expectFullyVisible(paintedRect(tester, 4, upper.last));
        follow(f, 2, mushaf: edition);
        await tester.pumpAndSettle();
        for (final line in upper) {
          expectFullyVisible(
            paintedRect(tester, 4, line),
            top: 16,
            bottom: 384,
          );
        }
        final comfortable = scroll.offset;
        follow(f, 3, mushaf: edition);
        await tester.pumpAndSettle();
        expect(scroll.offset, comfortable);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
    testWidgets(
      '$edition oversized ayah reveals its first complete line rather than a visible middle line',
      (tester) async {
        size(tester, const Size(800, 400));
        const lines = [
          Rect.fromLTWH(.1, .1, .8, .04),
          Rect.fromLTWH(.1, .5, .8, .04),
          Rect.fromLTWH(.1, .95, .8, .04),
        ];
        final f = AudioVerticalFollower(
          rectsFor: (page, surah, ayah, mushaf) => page == 4 ? lines : [],
        )..configureView(layoutIdentity: 'oversized', visiblePages: [4, 5]);
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
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(paintedRect(tester, 4, lines.first).bottom, lessThan(0));
        expectFullyVisible(paintedRect(tester, 4, lines[1]));
        follow(f, 1, mushaf: edition);
        await tester.pumpAndSettle();
        expect(paintedRect(tester, 4, lines.first).top, closeTo(16, .02));
        expectFullyVisible(paintedRect(tester, 4, lines.first));
        final firstLines = scroll.offset;
        follow(f, 1, mushaf: edition);
        await tester.pumpAndSettle();
        expect(scroll.offset, firstLines);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
    testWidgets(
      '$edition single-page audio preserves valid pinch zoom and manual panning',
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
        final originalFrame = tester.getRect(
          find.byKey(const ValueKey('quran-page-4')),
        );
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(viewer.maxScale, greaterThanOrEqualTo(1.4));
        expect(viewer.panEnabled, isTrue);
        expect(viewer.boundaryMargin, EdgeInsets.zero);
        for (final ayah in [1, 2, 3]) {
          follow(f, ayah, mushaf: edition);
          await tester.pumpAndSettle();
          expect(transform.value.storage, orderedEquals(original));
          expect(
            tester.getRect(find.byKey(const ValueKey('quran-page-4'))),
            originalFrame,
          );
        }

        await tester.timedDragFrom(
          const Offset(200, 400),
          const Offset(0, -150),
          const Duration(milliseconds: 300),
        );
        await tester.pumpAndSettle();
        expect(transform.value.storage[13], lessThan(original[13]));
        for (var i = 0; i < 16; i++) {
          if (i != 13) expect(transform.value.storage[i], original[i]);
        }
        final manuallyPositioned = List<double>.of(transform.value.storage);
        await tester.pump(const Duration(milliseconds: 700));
        follow(f, 4, mushaf: edition);
        await tester.pumpAndSettle();
        expect(transform.value.storage, orderedEquals(manuallyPositioned));
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .boundaryMargin,
          EdgeInsets.zero,
        );
        final frame = tester.getRect(
          find.byKey(const ValueKey('quran-page-4')),
        );
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
      expectFullyVisible(
        paintedRect(tester, page, const Rect.fromLTWH(.1, .88, .8, .05)),
        top: 36,
        bottom: 334,
      );
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
      final paging = ReaderPaging(initialPage: 1, lastPage: 3)
        ..configure(ReaderPageMode.single);
      final commits = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuranPageTurnView(
              paging: paging,
              layout: ReaderLayout.resolve(size: const Size(400, 800)),
              layoutIdentity: 'portrait',
              isDarkMode: false,
              onPageChanged: commits.add,
              buildSurface: (index, active, wrapLeaf) =>
                  QuranPageView.singlePage(
                    logicalPage: index + 1,
                    wrapLeaf: wrapLeaf,
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
      expect(commits, isEmpty);
      await tester.dragFrom(const Offset(60, 400), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(commits, [2]);
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
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
      final f = follower(6);
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
      final navigating = paging.goTo(6, animate: true);
      refresh(() {});
      final done = f.revealAfterNavigation(request, navigating);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scrolls(tester).every((s) => s.offset == 0), isTrue);
      await tester.pumpAndSettle();
      await done;
      expect(paging.visiblePages, [6, 7]);
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
      final nextNavigation = paging.goTo(8, animate: true);
      refresh(() {});
      final cancelled = f.revealAfterNavigation(pending, nextNavigation);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      await cancelled;
      expect(paging.focusedPage, 8);
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
    'a fitted portrait page gains no audio offset or margin around safe insets and controls',
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
      final frame = tester.getRect(find.byKey(const ValueKey('quran-page-4')));
      final original = List<double>.of(transform.value.storage);
      expect(frame.top, 0);
      expect(frame.bottom, 800);
      for (final ayah in [1, 2]) {
        follow(f, ayah);
        await tester.pumpAndSettle();
        expect(transform.value.storage, orderedEquals(original));
        expect(
          tester.getRect(find.byKey(const ValueKey('quran-page-4'))),
          frame,
        );
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(viewer.boundaryMargin, EdgeInsets.zero);
        expect(viewer.panEnabled, isFalse);
      }
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      transform.dispose();
    },
  );
  for (final device in [
    (name: 'phone', size: const Size(400, 800), folded: false),
    (name: 'tablet', size: const Size(800, 1280), folded: false),
    (name: 'flat fold', size: const Size(669, 951), folded: true),
    (name: 'narrow landscape', size: const Size(500, 400), folded: false),
  ]) {
    testWidgets(
      '${device.name} fitted single page stays fixed as audio and floating controls change',
      (tester) async {
        size(tester, device.size);
        final dockGeometry = GlobalKey();
        var expanded = true;
        late StateSetter refresh;
        List<Rect> obstructions() {
          if (!expanded) return const [];
          final box = dockGeometry.currentContext?.findRenderObject();
          if (box is! RenderBox || !box.hasSize) return const [];
          return [
            MatrixUtils.transformRect(
              box.getTransformTo(null),
              Offset.zero & box.size,
            ),
          ];
        }

        const lastLine = Rect.fromLTWH(.1, .94, .8, .05);
        const firstLine = Rect.fromLTWH(.1, .01, .8, .04);
        final f =
            AudioVerticalFollower(
              rectsFor: (page, surah, ayah, mushaf) =>
                  page == 4 ? [ayah == 2 ? firstLine : lastLine] : [],
              obstructions: obstructions,
            )..configureView(
              layoutIdentity: 'floating-controls',
              visiblePages: [4],
            );
        final transform = TransformationController();
        final layout = ReaderLayout.resolve(
          size: device.size,
          displayFeatures: device.folded
              ? [
                  ui.DisplayFeature(
                    bounds: Rect.fromLTWH(
                      device.size.width / 2,
                      0,
                      0,
                      device.size.height,
                    ),
                    type: ui.DisplayFeatureType.fold,
                    state: ui.DisplayFeatureState.postureFlat,
                  ),
                ]
              : const [],
        );
        expect(layout.singlePage, isTrue);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppPalette.emerald.toThemeData().copyWith(
              platform: TargetPlatform.android,
            ),
            home: StatefulBuilder(
              builder: (context, update) {
                refresh = update;
                return Scaffold(
                  body: Stack(
                    children: [
                      QuranPageView.singlePage(
                        logicalPage: 4,
                        pageScale: 1,
                        imagePath: (_) => image,
                        isDarkMode: false,
                        transformationController: transform,
                        verticalFollower: f,
                        fullWidthPortrait:
                            layout.sizing == ReaderPageSizing.portraitHeight,
                        fitToViewport:
                            layout.sizing == ReaderPageSizing.regionFit,
                        viewportBounds: layout.usableContentBounds,
                      ),
                      ReaderDockOverlay(
                        layout: layout,
                        child: ReaderDock(
                          geometryKey: dockGeometry,
                          placement: layout.dockPlacement,
                          expanded: expanded,
                          onToggle: () => refresh(() => expanded = !expanded),
                          palette: AppPalette.emerald,
                          zoom: const SizedBox(width: 40, height: 40),
                          actions: [
                            IconButton(
                              onPressed: () {},
                              icon: const Icon(Icons.book),
                            ),
                          ],
                          contextControls: ReaderAudioControls(
                            portrait: layout.bottomDock,
                            palette: AppPalette.emerald,
                            title: 'Al-Baqarah',
                            reference: '2:7',
                            subtitle: 'Recitation',
                            playing: true,
                            onPrevious: () {},
                            onPlayPause: () {},
                            onNext: () {},
                            onStop: () {},
                            onSettings: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dock = obstructions().single;
        final frame = tester.getRect(
          find.byKey(const ValueKey('quran-page-4')),
        );
        final original = List<double>.of(transform.value.storage);
        void expectUnchanged() {
          expect(transform.value.storage, orderedEquals(original));
          expect(
            tester.getRect(find.byKey(const ValueKey('quran-page-4'))),
            frame,
          );
          final viewer = tester.widget<InteractiveViewer>(
            find.byType(InteractiveViewer),
          );
          expect(viewer.boundaryMargin, EdgeInsets.zero);
          expect(viewer.panEnabled, isFalse);
        }

        expect(frame.top, closeTo(0, .01));
        expect(frame.bottom, closeTo(device.size.height, .01));
        expectUnchanged();
        if (layout.bottomDock) {
          expect(
            dock.bottom,
            lessThan(device.size.height - 3),
            reason: 'Controls float above the edge',
          );
          expect(paintedRect(tester, 4, lastLine).overlaps(dock), isTrue);
        }
        for (final ayah in [1, 2]) {
          follow(f, ayah);
          await tester.pumpAndSettle();
          expectUnchanged();
        }

        await tester.tap(find.byTooltip('Collapse navigation'));
        await tester.pumpAndSettle();
        expect(obstructions(), isEmpty);
        expectUnchanged();
        follow(f, 3);
        await tester.pumpAndSettle();
        expectUnchanged();
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
        expect(obstructions(), isNotEmpty);
        expectUnchanged();
        follow(f, 4);
        await tester.pumpAndSettle();
        expectUnchanged();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
        transform.dispose();
      },
    );
  }
  for (final zoom in [1.0, 1.4]) {
    testWidgets(
      'disabling audio follow at ${zoom}x removes old clearance and preserves legal manual positioning',
      (tester) async {
        size(tester, const Size(400, 800));
        final f = AudioVerticalFollower(
          rectsFor: (page, surah, ayah, mushaf) => const [
            Rect.fromLTWH(.1, .94, .8, .05),
          ],
          obstructions: () => const [Rect.fromLTWH(0, 680, 400, 120)],
        )..configureView(layoutIdentity: 'toggle-follow', visiblePages: [4]);
        final transform = TransformationController(
          Matrix4.identity()
            ..setEntry(0, 0, zoom)
            ..setEntry(1, 1, zoom)
            ..setEntry(0, 3, zoom == 1 ? 0 : -35)
            ..setEntry(1, 3, zoom == 1 ? 0 : -150),
        );
        final original = List<double>.of(transform.value.storage);
        var followAudio = true;
        late StateSetter refresh;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, update) {
                refresh = update;
                return Scaffold(
                  body: AudioVerticalViewport(
                    pages: const [4],
                    transformed: true,
                    followAudio: followAudio,
                    follower: f,
                    transformationController: transform,
                    builder: (handle) => InteractiveViewer(
                      transformationController: handle.transform,
                      minScale: 1,
                      maxScale: 1 / .7,
                      panAxis: PanAxis.vertical,
                      panEnabled: handle.verticalPanEnabled,
                      boundaryMargin: handle.boundaryMargin,
                      child: SizedBox(
                        width: 400,
                        height: 800,
                        child: Center(
                          child: SizedBox(
                            key: handle.pageKey(4),
                            width: 400,
                            height: zoom == 1 ? 800 : 560,
                            child: const ColoredBox(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (zoom == 1) {
          follow(f, 1);
          await tester.pumpAndSettle();
          expect(transform.value.storage[13], lessThan(0));
          expect(
            tester
                .widget<InteractiveViewer>(find.byType(InteractiveViewer))
                .boundaryMargin
                .bottom,
            greaterThan(0),
          );
        }

        refresh(() => followAudio = false);
        await tester.pumpAndSettle();
        expect(transform.value.storage, orderedEquals(original));
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        expect(viewer.boundaryMargin, EdgeInsets.zero);
        expect(viewer.panEnabled, zoom > 1);
        follow(f, 2);
        await tester.pumpAndSettle();
        expect(transform.value.storage, orderedEquals(original));
        await tester.pumpWidget(const SizedBox());
        f.dispose();
        transform.dispose();
      },
    );
  }
  testWidgets(
    'a side obstruction uses a reachable clear band and extends the scroll boundary when needed',
    (tester) async {
      size(tester, const Size(1400, 800));
      const obstruction = Rect.fromLTRB(1200, 250, 1400, 600);
      late Rect line;
      final f =
          AudioVerticalFollower(
            rectsFor: (page, surah, ayah, mushaf) => page == 4 ? [line] : [],
            obstructions: () => const [obstruction],
          )..configureView(
            layoutIdentity: 'side-obstruction',
            visiblePages: [4, 5],
          );
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
      final frame = tester.getRect(find.byKey(const ValueKey('quran-page-4')));
      line = Rect.fromLTRB(
        .1,
        (450 - frame.top) / frame.height,
        .9,
        (500 - frame.top) / frame.height,
      );
      final scroll = scrolls(tester).single;
      final originalExtent = scroll.position.maxScrollExtent;
      expect(scroll.offset, 0);
      expect(paintedRect(tester, 4, line).overlaps(obstruction), isTrue);
      follow(f, 1);
      await tester.pumpAndSettle();
      final revealed = paintedRect(tester, 4, line);
      expectFullyVisible(revealed, bottom: obstruction.top - 4);
      expect(revealed.overlaps(obstruction), isFalse);
      expect(
        scroll.offset,
        greaterThan(originalExtent),
        reason: 'The reachable upper band needs additional end clearance',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
  testWidgets(
    'fitted book pages stay visible and registered while audio follows',
    (tester) async {
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
      final before = tester.getRect(find.byKey(const ValueKey('quran-page-4')));
      follow(f, 1);
      await tester.pumpAndSettle();
      expect(scrolls(tester), isEmpty);
      final frame = tester.getRect(find.byKey(const ValueKey('quran-page-4')));
      expect(frame, before);
      expect(layout.pageRegions[1].contains(frame.topLeft), isTrue);
      expect(frame.bottom, lessThanOrEqualTo(layout.pageRegions[1].bottom));
      expect(frame.left, greaterThanOrEqualTo(490));
      await tester.pumpWidget(const SizedBox());
      f.dispose();
      paging.dispose();
    },
  );
}
