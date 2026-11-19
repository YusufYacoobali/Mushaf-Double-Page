import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/audio_page_follower.dart';
import 'package:mushaf_two_page/utils/audio_vertical_follower.dart';
import 'package:mushaf_two_page/utils/ios_display_regions.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

void main() {
  const window = Size(951, 669);
  const insets = EdgeInsets.fromLTRB(8, 24, 12, 21);
  // Deliberately off-centre: neither platform may invent a 50% hinge.
  const hinge = DisplayFeature(
    bounds: Rect.fromLTWH(400, 0, 24, 669),
    type: DisplayFeatureType.hinge,
    state: DisplayFeatureState.postureHalfOpened,
  );
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ordinary phones and tablets retain legacy page sizing', () {
    for (final (size, ipad, iosPhone, mode) in [
      (const Size(390, 844), false, true, ReaderPageMode.single),
      (const Size(844, 390), false, true, ReaderPageMode.spread),
      (const Size(390, 844), false, false, ReaderPageMode.single),
      (const Size(844, 390), false, false, ReaderPageMode.spread),
      (const Size(744, 1133), true, false, ReaderPageMode.single),
      (const Size(1133, 744), true, false, ReaderPageMode.spread),
      (const Size(1024, 1366), true, false, ReaderPageMode.single),
      (const Size(1366, 1024), true, false, ReaderPageMode.spread),
    ]) {
      final layout = ReaderLayout.resolve(
        size: size,
        preserveLegacyIPadPortrait: ipad,
        iosPhoneWidePortrait: iosPhone,
      );
      expect(
        layout.fitPagesToViewport,
        isFalse,
        reason: '$size must use its unchanged non-foldable sizing',
      );
      expect(layout.pageMode, mode, reason: '$size layout mode changed');
    }
    // The native iPad guard wins even if a device sends foldable hints.
    final ipadWithHints = ReaderLayout.resolve(
      size: const Size(744, 1133),
      preserveLegacyIPadPortrait: true,
      iosPhoneWidePortrait: true,
      foldedCover: true,
    );
    expect(ipadWithHints.fitPagesToViewport, isFalse);
    expect(ipadWithHints.pageMode, ReaderPageMode.single);
  });

  test('foldable bounds and page sizing are selected independently', () {
    final folded = ReaderLayout.resolve(
      size: const Size(466, 678),
      foldedCover: true,
      iosPhoneWidePortrait: true,
    );
    final openPortrait = ReaderLayout.resolve(
      size: const Size(669, 951),
      iosPhoneWidePortrait: true,
    );
    final openLandscape = ReaderLayout.resolve(
      size: const Size(951, 669),
      iosPhoneWidePortrait: true,
    );
    final androidBook = ReaderLayout.resolve(
      size: window,
      displayFeatures: const [hinge],
    );
    for (final layout in [folded, openPortrait, openLandscape, androidBook]) {
      expect(layout.fitPagesToViewport, isTrue);
    }
    expect(folded.pageMode, ReaderPageMode.single);
    expect(openPortrait.pageMode, ReaderPageMode.single);
    expect(openLandscape.pageMode, ReaderPageMode.spread);
    expect(androidBook.pageMode, ReaderPageMode.dualScreenBook);
  });

  for (final state in [
    DisplayFeatureState.unknown,
    DisplayFeatureState.postureFlat,
  ]) {
    test('$state never activates book mode', () {
      final layout = ReaderLayout.resolve(
        size: window,
        displayFeatures: [
          DisplayFeature(bounds: hinge.bounds, type: hinge.type, state: state),
        ],
      );
      expect(layout.pageMode, isNot(ReaderPageMode.dualScreenBook));
    });
  }
  for (final type in [DisplayFeatureType.fold, DisplayFeatureType.hinge]) {
    test('landscape horizontal half-open $type uses one readable pane', () {
      const obstruction = Rect.fromLTWH(0, 350, 1200, 20);
      final layout = ReaderLayout.resolve(
        size: const Size(1200, 800),
        displayFeatures: [
          DisplayFeature(
            bounds: obstruction,
            type: type,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      );
      expect(layout.pageMode, ReaderPageMode.single);
      expect(layout.pageRegions.single.overlaps(obstruction), isFalse);
      expect(layout.controlsRegion.overlaps(obstruction), isFalse);
      expect(layout.pageRegions.single.height, greaterThan(260));
    });
  }
  test('partial cutouts and hinges do not project across an entire panel', () {
    for (final type in [DisplayFeatureType.cutout, DisplayFeatureType.hinge]) {
      expect(
        safeDisplayRegions(window, insets, [
          DisplayFeature(
            bounds: const Rect.fromLTWH(390, 0, 30, 40),
            type: type,
            state: type == DisplayFeatureType.cutout
                ? DisplayFeatureState.unknown
                : DisplayFeatureState.postureHalfOpened,
          ),
        ]),
        safeDisplayRegions(window, insets, []),
      );
    }
  });
  test(
    'native geometry rejects malformed regions and retains real offsets',
    () {
      final native = IosDisplayRegions.fromEvent({
        'width': 951,
        'height': 669,
        'divisions': [
          {'left': 400, 'top': 0, 'width': 24, 'height': 669, 'active': true},
          {'left': 10, 'top': 0, 'width': -1, 'height': 669, 'active': true},
          {
            'left': double.nan,
            'top': 0,
            'width': 20,
            'height': 669,
            'active': true,
          },
        ],
      });
      expect(native.forSize(window).single.bounds, hinge.bounds);
      expect(native.forSize(const Size(669, 951)), isEmpty);
    },
  );

  late Directory fixtures;
  late String image;
  setUpAll(() async {
    await PageAyahIndex.load();
    fixtures = await Directory.systemTemp.createTemp('fitted_book_');
    image = '${fixtures.path}/page.png';
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final frame = await picture.toImage(72, 106);
    final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
    await File(image).writeAsBytes(bytes!.buffer.asUint8List());
    frame.dispose();
    picture.dispose();
  });
  tearDownAll(() => fixtures.delete(recursive: true));

  testWidgets(
    'folding keeps focused selection, audio and persistence on the same page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = window;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final paging = ReaderPaging(initialPage: 4, lastPage: 851);
      final audio = AudioPageFollower();
      final measured = <int>[];
      final vertical = AudioVerticalFollower(
        rectsFor: (page, surah, ayah, mushaf) {
          measured.add(page);
          return page == 5 ? const [Rect.fromLTWH(.2, .3, .4, .05)] : [];
        },
      );
      final persisted = <int>[];
      var selected = 5, book = true, cover = false;
      var cycle = 0;
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) {
              refresh = update;
              return Scaffold(
                body: LayoutBuilder(
                  builder: (context, constraints) {
                    final layout = ReaderLayout.resolve(
                      size: constraints.biggest,
                      iosPhoneWidePortrait: true,
                      foldedCover: cover,
                      displayFeatures: book ? [hinge] : [],
                    );
                    return AdaptiveQuranPages(
                      paging: paging,
                      layout: layout,
                      singleScale: .8,
                      spreadScale: 1,
                      imagePath: (_) => image,
                      isDarkMode: false,
                      aspectRatio: QuranPageView.pageAspectRatio,
                      highlightFor: (page) => page == selected
                          ? const [Rect.fromLTWH(.2, .3, .4, .05)]
                          : [],
                      highlightColor: Colors.amber,
                      verticalFollower: vertical,
                      onFocus: persisted.add,
                      onPageChanged: persisted.add,
                      onTap: (page, x, y) => refresh(() => selected = page),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The left leaf is page 5; focusing it must survive every subsequent mode.
      await tester.tap(find.byKey(const ValueKey('quran-page-5')));
      // Playback yields to manual interaction for the existing idle interval.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(paging.focusedPage, 5);
      expect(persisted, [5]);
      final verse = PageAyahIndex.ayahsForPage(
        5,
        mushaf: 'indopak_tajweed',
      ).last;
      Future<void> expectFollowing() async {
        expect(paging.focusedPage, 5);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('quran-page-5')),
            matching: find.byType(CustomPaint),
          ),
          findsOneWidget,
        );
        expect(
          audio.targetPage(
            playing: true,
            session: 1,
            cycle: ++cycle,
            surah: verse.surah,
            ayah: verse.ayah,
            currentPage: paging.focusedPage,
            portrait: paging.singlePage,
            mushaf: 'indopak_tajweed',
            visiblePages: paging.visiblePages,
            sequentialBook: paging.book,
          ),
          isNull,
        );
        measured.clear();
        final request = vertical.beginAyah(
          playing: true,
          visible: true,
          session: 1,
          cycle: cycle,
          surah: verse.surah,
          ayah: verse.ayah,
          mushaf: 'indopak_tajweed',
        );
        vertical.reveal(request!);
        await tester.pumpAndSettle();
        expect(measured, contains(5));
        expect(persisted, [5]);
      }

      await expectFollowing();
      for (final stage in [
        (const Size(466, 678), false, true),
        (const Size(669, 951), false, false),
        (window, false, false),
        (window, true, false),
      ]) {
        tester.view.physicalSize = stage.$1;
        refresh(() {
          book = stage.$2;
          cover = stage.$3;
        });
        await tester.pumpAndSettle();
        await expectFollowing();
      }
      // Returning to a book anchors page 5 on the right, with page 6 on the left.
      expect(
        tester.getRect(find.byKey(const ValueKey('quran-page-5'))).left,
        greaterThanOrEqualTo(hinge.bounds.right),
      );
      await tester.pumpWidget(const SizedBox());
      vertical.dispose();
      paging.dispose();
    },
  );

  for (final portrait in [
    const Size(744, 1133),
    const Size(834, 1194),
    const Size(1024, 1366),
  ]) {
    for (final landscape in [false, true]) {
      testWidgets(
        'v5 iPad page geometry at $portrait landscape=$landscape is unchanged',
        (tester) async {
          final size = landscape
              ? Size(portrait.height, portrait.width)
              : portrait;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final paging = ReaderPaging(initialPage: 237, lastPage: 851);
          final layout = ReaderLayout.resolve(
            size: size,
            padding: insets,
            preserveLegacyIPadPortrait: true,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AdaptiveQuranPages(
                  paging: paging,
                  layout: layout,
                  singleScale: .8,
                  spreadScale: .7,
                  imagePath: (_) => image,
                  isDarkMode: false,
                  aspectRatio: QuranPageView.pageAspectRatio,
                  highlightFor: (_) => const [],
                  highlightColor: Colors.amber,
                  onPageChanged: (_) {},
                  onFocus: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final page = tester.getRect(
            find.byKey(const ValueKey('quran-page-237')),
          );
          if (landscape) {
            final other = tester.getRect(
              find.byKey(const ValueKey('quran-page-236')),
            );
            final width = (size.width - 1) / 2 * .7;
            expect(page.width, closeTo(width, .001));
            expect(
              page.height,
              closeTo(width / QuranPageView.pageAspectRatio, .001),
            );
            expect(page.top, 0);
            expect(other.left - page.right, closeTo(1, .001));
            expect(
              page.expandToInclude(other).center.dx,
              closeTo(size.width / 2, .001),
            );
          } else {
            expect(page.width, size.width);
            expect(page.height, closeTo(size.height * .8, .001));
            expect(page.center.dx, closeTo(size.width / 2, .001));
            expect(page.center.dy, closeTo(size.height / 2, .001));
          }
          expect(paging.focusedPage, 237);
          await tester.pumpWidget(const SizedBox());
          paging.dispose();
        },
      );
    }
  }

  for (final scenario in [
    ('folded portrait', const Size(466, 678), true),
    ('asymmetric folded portrait', const Size(401, 755), true),
    ('folded landscape', const Size(678, 466), true),
    ('open portrait', const Size(669, 951), false),
    ('open landscape', const Size(951, 669), false),
  ]) {
    for (final edition in ['indopak_tajweed', 'madani']) {
      testWidgets(
        '${scenario.$1} $edition uses posture-specific zoom behind the dock',
        (tester) async {
          final size = scenario.$2;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final portrait = size.height > size.width;
          final sharedScroll = !portrait && !scenario.$3;
          final padding = scenario.$1 == 'folded portrait'
              ? const EdgeInsets.only(right: 84, bottom: 34)
              : insets;
          tester.view.padding = tester.view.viewPadding = FakeViewPadding(
            left: padding.left,
            top: padding.top,
            right: padding.right,
            bottom: padding.bottom,
          );
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
          final safe = Rect.fromLTRB(
            padding.left,
            padding.top,
            size.width - padding.right,
            size.height - padding.bottom,
          );
          final reading = portrait
              ? Rect.fromLTRB(safe.left, 0, safe.right, size.height)
              : safe;
          (int, double, double)? tap;
          final aspect = QuranPageView.aspectRatioForMushaf(edition);
          final paging = ReaderPaging(initialPage: 4, lastPage: 851);
          final dockKey = GlobalKey();
          var expanded = false;
          var showContext = false;
          var zoom = 1.0;
          late StateSetter refresh;
          late ReaderLayout layout;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              home: StatefulBuilder(
                builder: (context, update) {
                  refresh = update;
                  layout = ReaderLayout.resolve(
                    size: size,
                    padding: MediaQuery.paddingOf(context),
                    foldedCover: scenario.$3,
                    iosPhoneWidePortrait: true,
                    pageAspectRatio: aspect,
                  );
                  return Scaffold(
                    body: Stack(
                      children: [
                        AdaptiveQuranPages(
                          paging: paging,
                          layout: layout,
                          singleScale: zoom,
                          spreadScale: zoom,
                          imagePath: (_) => image,
                          isDarkMode: false,
                          aspectRatio: aspect,
                          highlightFor: (_) => const [
                            Rect.fromLTWH(.2, .3, .1, .1),
                          ],
                          onTap: (p, x, y) => tap = (p, x, y),
                          highlightColor: Colors.amber,
                          onPageChanged: (_) {},
                          onFocus: (_) {},
                        ),
                        ReaderDockOverlay(
                          layout: layout,
                          child: ReaderDock(
                            geometryKey: dockKey,
                            placement: layout.dockPlacement,
                            expanded: expanded,
                            onToggle: () => refresh(() => expanded = !expanded),
                            palette: AppPalette.emerald,
                            zoom: SizedBox(
                              width: layout.bottomDock ? 100 : 40,
                              height: layout.bottomDock ? 32 : 120,
                            ),
                            actions: [
                              for (var i = 0; i < 5; i++)
                                IconButton(
                                  icon: const Icon(Icons.book),
                                  onPressed: () {},
                                ),
                            ],
                            contextControls: showContext
                                ? const SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Icon(Icons.play_arrow),
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
          );
          await tester.pumpAndSettle();
          Map<int, Rect> pages() => {
            for (final page in layout.singlePage ? [4] : [4, 5])
              page: tester.getRect(find.byKey(ValueKey('quran-page-$page'))),
          };
          final maximum = pages();
          void expectMaximumUnchanged() {
            expect(layout.usableContentBounds, reading);
            expect(
              pages(),
              maximum,
              reason: 'Floating controls must not resize or shift the pages',
            );
          }

          expect(layout.fitPagesToViewport, isTrue);
          expect(layout.safeRegions, [safe]);
          expect(layout.usableContentBounds, reading);
          if (portrait) {
            expect(maximum[4], reading);
          } else if (sharedScroll) {
            expect(maximum[5]!.left, safe.left);
            expect(maximum[4]!.right, safe.right);
            expect(maximum[4]!.left - maximum[5]!.right, 1);
            for (final page in maximum.values) {
              expect(page.top, safe.top);
              expect(page.width, (safe.width - 1) / 2);
              expect(page.height, closeTo(page.width / aspect, .001));
            }
          } else {
            final page = maximum[4]!;
            expect((page.center - safe.center).distance, lessThan(.001));
            expect(page.height, safe.height);
            expect(page.width, closeTo(safe.height * aspect, .001));
          }

          Future<void> toggleDock() async {
            await tester.tap(find.byType(NavigationPullTab));
            await tester.pump(const Duration(milliseconds: 100));
            expectMaximumUnchanged();
            await tester.pumpAndSettle();
            expectMaximumUnchanged();
          }

          final collapsedDock = tester.getRect(find.byKey(dockKey));
          if (portrait) {
            final tab = tester.getRect(find.byTooltip('Open navigation'));
            expect(tab.bottom, size.height - 16);
            expect(tab.center.dx, reading.center.dx);
          }
          await toggleDock();
          final expandedDock = tester.getRect(find.byKey(dockKey));
          expect(
            layout.bottomDock ? expandedDock.height : expandedDock.width,
            greaterThan(
              layout.bottomDock ? collapsedDock.height : collapsedDock.width,
            ),
          );
          if (portrait) {
            expect(expandedDock.bottom, size.height - padding.bottom);
            expect(
              maximum[4]!.overlaps(expandedDock),
              isTrue,
              reason: 'Portrait pages must continue under the floating bar',
            );
          }

          refresh(() => showContext = true);
          await tester.pump(const Duration(milliseconds: 100));
          expectMaximumUnchanged();
          await tester.pumpAndSettle();
          expectMaximumUnchanged();
          final contextDock = tester.getRect(find.byKey(dockKey));
          expect(
            layout.bottomDock ? contextDock.height : contextDock.width,
            greaterThan(
              layout.bottomDock ? expandedDock.height : expandedDock.width,
            ),
          );
          await toggleDock();
          refresh(() => showContext = false);
          await tester.pumpAndSettle();
          expectMaximumUnchanged();
          await toggleDock();

          for (final value in [layout.singlePage ? .7 : .6, .85, .95]) {
            refresh(() => zoom = value);
            await tester.pumpAndSettle();
            for (final entry in pages().entries) {
              expect(
                entry.value.width,
                closeTo(
                  maximum[entry.key]!.width * (portrait ? 1 : value),
                  .001,
                ),
              );
              if (portrait) {
                expect(
                  (entry.value.center - reading.center).distance,
                  lessThan(.001),
                );
              } else if (sharedScroll) {
                expect(entry.value.top, reading.top);
                expect(
                  pages()[4]!.expandToInclude(pages()[5]!).center.dx,
                  closeTo(reading.center.dx, .001),
                );
              }
              expect(
                entry.value.height,
                closeTo(maximum[entry.key]!.height * value, .001),
              );
            }
            expect(layout.usableContentBounds, reading);
          }
          refresh(() => zoom = 1);
          await tester.pumpAndSettle();
          expectMaximumUnchanged();
          final scroll = find.descendant(
            of: find.byType(AdaptiveQuranPages),
            matching: find.byType(SingleChildScrollView),
          );
          expect(scroll, sharedScroll ? findsOneWidget : findsNothing);
          if (sharedScroll) {
            final initial = pages();
            await tester.dragFrom(initial[4]!.center, const Offset(0, -200));
            await tester.pumpAndSettle();
            for (final entry in pages().entries) {
              expect(
                initial[entry.key]!.top - entry.value.top,
                closeTo(entry.value.height - reading.height, .001),
              );
              expect(entry.value.bottom, closeTo(reading.bottom, .001));
            }
            expect(paging.focusedPage, 4);
            expect(paging.visiblePages, [4, 5]);
          }
          final frame = pages()[4]!;
          final target =
              frame.topLeft + Offset(.25 * frame.width, .35 * frame.height);
          final highlight = find.descendant(
            of: find.byKey(const ValueKey('quran-page-4')),
            matching: find.byType(CustomPaint),
          );
          expect(tester.getRect(highlight), frame);
          await tester.tapAt(target);
          await tester.pumpAndSettle();
          expect(tap?.$1, 4);
          expect(tap?.$2, closeTo(.25, .001));
          expect(tap?.$3, closeTo(.35, .001));
          if (sharedScroll) {
            await tester.flingFrom(
              const Offset(200, 300),
              const Offset(550, 0),
              1200,
            );
            await tester.pumpAndSettle();
            expect(paging.visiblePages, [6, 7]);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          paging.dispose();
        },
      );
    }
  }

  for (final edition in ['indopak_tajweed', 'madani']) {
    for (final scale in [.6, 1.0]) {
      testWidgets(
        '$edition book at $scale fits complete RTL pages in actual panels',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = window;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final paging = ReaderPaging(initialPage: 4, lastPage: 851);
          final layout = ReaderLayout.resolve(
            size: window,
            padding: insets,
            displayFeatures: [hinge],
          );
          final aspect = QuranPageView.aspectRatioForMushaf(edition);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AdaptiveQuranPages(
                  paging: paging,
                  layout: layout,
                  singleScale: .8,
                  spreadScale: scale,
                  imagePath: (_) => image,
                  isDarkMode: false,
                  aspectRatio: aspect,
                  highlightFor: (_) => const [Rect.fromLTWH(.2, .3, .4, .05)],
                  highlightColor: Colors.amber,
                  onPageChanged: (_) {},
                  onFocus: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final (page, physical) in [(4, 1), (5, 0)]) {
            final frame = tester.getRect(
              find.byKey(ValueKey('quran-page-$page')),
            );
            final panel = layout.pageRegions[physical];
            expect(frame.left, greaterThanOrEqualTo(panel.left - .001));
            expect(frame.top, greaterThanOrEqualTo(panel.top - .001));
            expect(frame.right, lessThanOrEqualTo(panel.right + .001));
            expect(frame.bottom, lessThanOrEqualTo(panel.bottom + .001));
            expect(frame.center.dx, closeTo(panel.center.dx, .001));
            expect(frame.center.dy, closeTo(panel.center.dy, .001));
            expect(frame.width / frame.height, closeTo(aspect, .001));
            expect(frame.overlaps(hinge.bounds), isFalse);
            expect(
              find.descendant(
                of: find.byKey(ValueKey('quran-page-$page')),
                matching: find.byType(CustomPaint),
              ),
              findsOneWidget,
            );
          }
          final current = tester.getRect(
            find.byKey(const ValueKey('quran-page-4')),
          );
          final next = tester.getRect(
            find.byKey(const ValueKey('quran-page-5')),
          );
          expect(next.width, closeTo(current.width, .001));
          expect(next.height, closeTo(current.height, .001));
          expect(find.byType(SingleChildScrollView), findsNothing);
          final short = await tester.startGesture(const Offset(540, 300));
          await short.moveTo(const Offset(600, 300));
          await tester.pump(const Duration(milliseconds: 250));
          await short.up();
          await tester.pumpAndSettle();
          expect(paging.visiblePages, [4, 5]);
          // One screen cannot provide a drag across half the combined window.
          // Pause before releasing to check distance-based snapping, not fling.
          final swipe = await tester.startGesture(const Offset(540, 300));
          await swipe.moveTo(const Offset(900, 300));
          await tester.pump(const Duration(milliseconds: 250));
          await swipe.up();
          await tester.pumpAndSettle();
          expect(paging.visiblePages, [6, 7]);
          expect(paging.focusedPage, 6);
          final back = await tester.startGesture(const Offset(780, 300));
          await back.moveTo(const Offset(480, 300));
          await tester.pump(const Duration(milliseconds: 250));
          await back.up();
          await tester.pumpAndSettle();
          expect(paging.visiblePages, [4, 5]);
          await tester.pumpWidget(const SizedBox());
          paging.dispose();
        },
      );
    }
  }

  for (final size in [
    const Size(1133, 744),
    const Size(1194, 834),
    const Size(1366, 1024),
    const Size(1100, 320),
    const Size(678, 466),
    window,
  ]) {
    testWidgets('landscape dock at $size is compact and vertically centred', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final cover = size == const Size(678, 466);
      final duo = size == window || cover;
      final layout = ReaderLayout.resolve(
        size: size,
        padding: cover ? const EdgeInsets.only(right: 24, bottom: 21) : insets,
        preserveLegacyIPadPortrait: !duo,
        foldedCover: cover,
        iosPhoneWidePortrait: duo,
        displayFeatures: duo && !cover ? [hinge] : [],
      );
      var expanded = false;
      late StateSetter refresh;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) {
              refresh = update;
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
                        zoom: const SizedBox(width: 40, height: 120),
                        actions: [
                          for (var i = 0; i < 5; i++)
                            IconButton(
                              tooltip: 'Action $i',
                              icon: const Icon(Icons.book),
                              onPressed: () {},
                            ),
                        ],
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
      final tab = find.byType(NavigationPullTab);
      expect(
        tester.getRect(tab).center.dy,
        closeTo(layout.controlsRegion.center.dy, .001),
      );
      await tester.tap(tab);
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const ValueKey('reader-navigation-panel')),
      );
      expect(panel.center.dy, closeTo(layout.controlsRegion.center.dy, .001));
      if (size.height < 400) {
        expect(panel.height, closeTo(layout.controlsRegion.height - 24, .001));
        final scroll = find.descendant(
          of: find.byKey(const ValueKey('reader-navigation-panel')),
          matching: find.byType(SingleChildScrollView),
        );
        final controller = tester
            .state<ScrollableState>(
              find.descendant(of: scroll, matching: find.byType(Scrollable)),
            )
            .position;
        expect(controller.maxScrollExtent, greaterThan(0));
        await tester.drag(scroll, const Offset(0, -240));
        await tester.pumpAndSettle();
      } else {
        expect(panel.height, lessThan(layout.controlsRegion.height - 24));
        for (var i = 0; i < 5; i++) {
          expect(find.byTooltip('Action $i').hitTestable(), findsOneWidget);
        }
      }
      if (duo && !cover) expect(panel.overlaps(hinge.bounds), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
