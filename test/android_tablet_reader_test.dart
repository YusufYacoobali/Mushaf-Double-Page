import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/reader_audio_controls.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const insets = EdgeInsets.only(top: 24, bottom: 24);

  for (final edition in ['indopak_tajweed', 'madani']) {
    for (final size in [
      const Size(600, 960),
      const Size(800, 1280),
      const Size(1280, 800),
      const Size(900, 900),
    ]) {
      test('$edition ordinary Android tablet matches iPad at $size', () {
        final ratio = QuranPageView.aspectRatioForMushaf(edition);
        // A regular Android tablet has neither an iPad hint nor fold features.
        final android = ReaderLayout.resolve(
          size: size,
          padding: insets,
          pageAspectRatio: ratio,
        );
        final ipad = ReaderLayout.resolve(
          size: size,
          padding: insets,
          pageAspectRatio: ratio,
          preserveLegacyIPadPortrait: true,
        );
        final portrait = size.height >= size.width;
        expect(
          android.pageMode,
          portrait ? ReaderPageMode.single : ReaderPageMode.spread,
        );
        expect(android.pageMode, ipad.pageMode);
        expect(android.dockPlacement, ipad.dockPlacement);
        expect(android.sizing, ipad.sizing);
        expect(android.fullWidthPortrait, ipad.fullWidthPortrait);
        expect(android.usableContentBounds, ipad.usableContentBounds);
        expect(android.pageRegions, ipad.pageRegions);
        expect(android.controlsRegion, ipad.controlsRegion);
        expect(android.centerSideDock, !portrait);
        expect(android.centerSideDock, ipad.centerSideDock);
        expect(
          android.centerShortLandscapeSpread,
          ipad.centerShortLandscapeSpread,
        );
        expect(android.fitPagesToViewport, isFalse);
      });
    }
  }

  test(
    'tablet display keeps its layout policy in a narrow landscape window',
    () {
      const window = Size(700, 500);
      final android = ReaderLayout.resolve(
        size: window,
        displaySize: const Size(800, 1280),
        padding: insets,
      );
      final ipad = ReaderLayout.resolve(
        size: window,
        padding: insets,
        preserveLegacyIPadPortrait: true,
      );
      expect(android.pageMode, ipad.pageMode);
      expect(android.sizing, ipad.sizing);
      expect(android.pageRegions, ipad.pageRegions);
      expect(android.controlsRegion, ipad.controlsRegion);
      expect(android.centerSideDock, isTrue);
      expect(android.centerSideDock, ipad.centerSideDock);

      final phone = ReaderLayout.resolve(
        size: const Size(844, 390),
        displaySize: const Size(390, 844),
      );
      expect(phone.pageMode, ReaderPageMode.spread);
      expect(phone.centerSideDock, isFalse);
      expect(phone.fitPagesToViewport, isFalse);
    },
  );

  test('large displays preserve fold, cover and iOS phone policies', () {
    const display = Size(800, 1280);
    final book = ReaderLayout.resolve(
      size: const Size(900, 1000),
      displaySize: display,
      displayFeatures: const [
        ui.DisplayFeature(
          bounds: Rect.fromLTWH(440, 0, 20, 1000),
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ],
    );
    expect(book.pageMode, ReaderPageMode.dualScreenBook);
    expect(book.fitPagesToViewport, isTrue);

    final cover = ReaderLayout.resolve(
      size: const Size(700, 500),
      displaySize: display,
      foldedCover: true,
    );
    expect(cover.pageMode, ReaderPageMode.single);
    expect(cover.fitPagesToViewport, isTrue);

    final phone = ReaderLayout.resolve(
      size: const Size(700, 500),
      displaySize: display,
      iosPhoneWidePortrait: true,
    );
    expect(phone.centerSideDock, isFalse);
    expect(phone.fitPagesToViewport, isFalse);
  });

  late Directory images;
  late String imagePath;
  setUpAll(() async {
    images = await Directory.systemTemp.createTemp('android_tablet_reader_');
    imagePath = '${images.path}/page.png';
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(64, 96);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(imagePath).writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  });
  tearDownAll(() => images.delete(recursive: true));

  for (final edition in ['indopak_tajweed', 'madani']) {
    testWidgets(
      '$edition Android tablet rotation and zoom keep the focused page',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 1280);
        tester.view.display.devicePixelRatio = 1;
        tester.view.display.size = const Size(800, 1280);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.display.resetDevicePixelRatio);
        addTearDown(tester.view.display.resetSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);

        final paging = ReaderPaging(initialPage: 237, lastPage: 624);
        addTearDown(paging.dispose);
        final visits = <int>[];
        final ratio = QuranPageView.aspectRatioForMushaf(edition);
        var singleScale = .8;
        var spreadScale = .7;
        var expanded = false;
        late ReaderLayout layout;
        late StateSetter refresh;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppPalette.emerald.toThemeData().copyWith(
              platform: TargetPlatform.android,
            ),
            home: StatefulBuilder(
              builder: (context, update) {
                refresh = update;
                return Scaffold(
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      final display = View.of(context).display;
                      layout = ReaderLayout.resolve(
                        size: constraints.biggest,
                        displaySize: display.size / display.devicePixelRatio,
                        padding: MediaQuery.paddingOf(context),
                        pageAspectRatio: ratio,
                      );
                      return Stack(
                        children: [
                          AdaptiveQuranPages(
                            paging: paging,
                            layout: layout,
                            singleScale: singleScale,
                            spreadScale: spreadScale,
                            imagePath: (_) => imagePath,
                            isDarkMode: false,
                            aspectRatio: ratio,
                            mushaf: edition,
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
                              onToggle: () =>
                                  refresh(() => expanded = !expanded),
                              palette: AppPalette.emerald,
                              zoom: ReaderZoom(
                                portrait: layout.bottomDock,
                                palette: AppPalette.emerald,
                                scale: layout.singlePage
                                    ? singleScale
                                    : spreadScale,
                                minimum: layout.singlePage ? .7 : .6,
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
          ),
        );
        await tester.pumpAndSettle();
        Rect page(int number) =>
            tester.getRect(find.byKey(ValueKey('quran-page-$number')));
        expect(paging.visiblePages, [237]);
        for (final scale in [.7, 1.0, .8]) {
          refresh(() => singleScale = scale);
          await tester.pumpAndSettle();
          final rect = page(237);
          expect(rect.width, closeTo(800, .001));
          expect(rect.height, closeTo(1280 * scale, .001));
          expect(rect.center.dy, closeTo(640, .001));
        }
        final portrait = page(237);
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
        expect(page(237), portrait);

        tester.view.physicalSize = const Size(1280, 800);
        tester.view.display.size = const Size(1280, 800);
        await tester.pumpAndSettle();
        expect(layout.pageMode, ReaderPageMode.spread);
        expect(paging.visiblePages, [236, 237]);
        for (final scale in [.6, 1.0, .7]) {
          refresh(() => spreadScale = scale);
          await tester.pumpAndSettle();
          final left = page(237), right = page(236);
          expect(left.width, closeTo((1280 - 1) / 2 * scale, .001));
          expect(right.width, closeTo(left.width, .001));
          expect(right.height, closeTo(left.height, .001));
          expect(left.width / left.height, closeTo(ratio, .001));
          expect(right.left - left.right, closeTo(1, .001));
        }
        final panel = tester.getRect(
          find.byKey(const ValueKey('reader-navigation-panel')),
        );
        expect(panel.center.dy, closeTo(layout.controlsRegion.center.dy, .001));
        expect(panel.height, lessThan(layout.controlsRegion.height - 24));
        await tester.tapAt(page(236).center);
        await tester.pump();
        expect(paging.focusedPage, 236);

        tester.view.physicalSize = const Size(800, 1280);
        tester.view.display.size = const Size(800, 1280);
        await tester.pumpAndSettle();
        expect(paging.visiblePages, [236]);
        expect(page(236).size, portrait.size);
        expect(
          visits,
          isEmpty,
          reason: 'Rotation and zoom are not page visits',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Android tablet side dock stays compact with and without audio', (
    tester,
  ) async {
    const size = Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.display.devicePixelRatio = 1;
    tester.view.display.size = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.display.resetDevicePixelRatio);
    addTearDown(tester.view.display.resetSize);
    late ReaderLayout layout;
    var withAudio = false, expanded = true;
    var actions = 0, audioActions = 0;
    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppPalette.emerald.toThemeData().copyWith(
          platform: TargetPlatform.android,
        ),
        home: MediaQuery(
          data: const MediaQueryData(size: size, padding: insets),
          child: StatefulBuilder(
            builder: (context, update) {
              refresh = update;
              final display = View.of(context).display;
              layout = ReaderLayout.resolve(
                size: size,
                displaySize: display.size / display.devicePixelRatio,
                padding: insets,
              );
              return Scaffold(
                body: Stack(
                  children: [
                    ReaderDockOverlay(
                      layout: layout,
                      child: ReaderDock(
                        placement: layout.dockPlacement,
                        expanded: expanded,
                        onToggle: () => refresh(() => expanded = !expanded),
                        palette: AppPalette.emerald,
                        zoom: const SizedBox(width: 40, height: 110),
                        actions: [
                          for (var i = 0; i < 5; i++)
                            IconButton(
                              tooltip: 'Tablet action $i',
                              icon: const Icon(Icons.book),
                              onPressed: () => actions++,
                            ),
                        ],
                        contextControls: withAudio
                            ? ReaderAudioControls(
                                portrait: false,
                                palette: AppPalette.emerald,
                                title: 'Al-Baqarah',
                                reference: '2:7',
                                subtitle: 'Recitation',
                                playing: true,
                                onPrevious: () => audioActions++,
                                onPlayPause: () => audioActions++,
                                onNext: () => audioActions++,
                                onStop: () => audioActions++,
                                onSettings: () => audioActions++,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Rect? previousPanel;
    for (final audio in [false, true]) {
      refresh(() => withAudio = audio);
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const ValueKey('reader-navigation-panel')),
      );
      expect(panel.center.dy, closeTo(layout.controlsRegion.center.dy, .001));
      expect(panel.height, lessThan(layout.controlsRegion.height * .75));
      expect(panel.width, 52);
      if (previousPanel != null) expect(panel.height, previousPanel.height);
      previousPanel = panel;
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byTooltip('Tablet action $i'));
      }
      if (audio) {
        final controls = tester.getRect(find.byType(ReaderAudioControls));
        expect(controls.center.dy, closeTo(panel.center.dy, .001));
        expect(controls.left, greaterThan(panel.right));
        expect(controls.height, lessThan(layout.controlsRegion.height * .75));
        expect(controls.right, lessThanOrEqualTo(size.width));
        await tester.tap(find.byTooltip('Pause'));
        await tester.tap(find.byTooltip('Stop audio'));
      }
    }
    expect(actions, 10);
    expect(audioActions, 2);
    await tester.tap(find.byTooltip('Collapse navigation'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Tablet action 0'), findsNothing);
    expect(
      tester.getRect(find.byType(NavigationPullTab)).center.dy,
      closeTo(layout.controlsRegion.center.dy, .001),
    );
    expect(tester.takeException(), isNull);
  });
}
