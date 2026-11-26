// flutter test --dart-define=PAGE_TURN_EVIDENCE_DIR=build/turn-frames
//   test/page_turn_capture_test.dart exports ten PNGs for every device profile.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/adaptive_quran_pages.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

const _evidence = String.fromEnvironment('PAGE_TURN_EVIDENCE_DIR');
const _bookHinge = ui.DisplayFeature(
  bounds: Rect.fromLTWH(400, 0, 24, 669),
  type: ui.DisplayFeatureType.hinge,
  state: ui.DisplayFeatureState.postureHalfOpened,
);

// Use the edition's printed preview beneath a large, asymmetric label. A
// reflected back face and a wrong leaf number can both be read in a small PNG.
Future<void> _makeFixtures(Directory dir, String edition) async {
  final data = await rootBundle.load('assets/mushaf/${edition}_preview.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final preview = (await codec.getNextFrame()).image;
  final height = (320 / QuranPageView.aspectRatioForMushaf(edition)).round();
  const colors = [
    Color(0xff27625b),
    Color(0xff8c542c),
    Color(0xff534771),
    Color(0xff416189),
  ];
  for (var page = 1; page <= 12; page++) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paper = Size(320, height.toDouble());
    final accent = colors[page % colors.length];
    canvas.drawColor(const Color(0xfff9f4e7), BlendMode.src);
    final pen = Paint()..color = accent;
    canvas.drawRect(Rect.fromLTWH(0, 0, paper.width, 78), pen);
    final title =
        (ui.ParagraphBuilder(ui.ParagraphStyle())
              ..pushStyle(
                ui.TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 47,
                  color: Colors.white,
                ),
              )
              ..addText('Folio $page'))
            .build()
          ..layout(const ui.ParagraphConstraints(width: 300));
    canvas.drawParagraph(title, const Offset(14, 8));
    title.dispose();
    final src = Rect.fromLTWH(
      0,
      0,
      preview.width.toDouble(),
      preview.height.toDouble(),
    );
    final dst = Alignment.center.inscribe(
      applyBoxFit(
        BoxFit.contain,
        src.size,
        Size(288, height - 140),
      ).destination,
      Rect.fromLTWH(16, 86, 288, height - 140),
    );
    canvas.drawImageRect(
      preview,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.drawRect(Rect.fromLTWH(16, height - 37, 288, 2), pen);
    canvas.drawRect(Rect.fromLTWH(16, height - 33, 46, 7), pen);
    final picture = recorder.endRecording();
    final image = await picture.toImage(320, height);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File(
      '${dir.path}/$edition-$page.png',
    ).writeAsBytes(png.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  }
  preview.dispose();
  codec.dispose();
}

typedef _Frame = ({Uint8List rgba, int width});

Future<_Frame> _frame(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    if (_evidence.isNotEmpty) {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('$_evidence/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png.buffer.asUint8List());
    }
    final width = image.width;
    image.dispose();
    return (rgba: pixels.buffer.asUint8List(), width: width);
  }))!;
}

double _changedFraction(
  _Frame before,
  _Frame after,
  Rect region, {
  int tolerance = 12,
}) {
  var samples = 0;
  var changed = 0;
  for (var y = region.top.ceil(); y < region.bottom.floor(); y += 4) {
    for (var x = region.left.ceil(); x < region.right.floor(); x += 4) {
      final i = (y * before.width + x) * 4;
      final changedPixel = const [0, 1, 2].any(
        (channel) =>
            (before.rgba[i + channel] - after.rgba[i + channel]).abs() >
            tolerance,
      );
      if (changedPixel) changed++;
      samples++;
    }
  }
  return changed / samples;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixtures;
  setUpAll(() async {
    fixtures = await Directory.systemTemp.createTemp('numbered-mushaf-leaves');
    final font = FontLoader('Inter')
      ..addFont(
        rootBundle.load('assets/fonts/Inter-VariableFont_opsz,wght.ttf'),
      );
    await font.load();
    for (final edition in ['indopak_tajweed', 'madani']) {
      await _makeFixtures(fixtures, edition);
    }
  });
  tearDownAll(() => fixtures.delete(recursive: true));

  void profile(
    String name,
    Size size, {
    bool ipad = false,
    bool ios = true,
    bool dark = false,
    bool book = false,
    bool flatFold = false,
    bool foldedCover = false,
    EdgeInsets? insets,
    String edition = 'indopak_tajweed',
    double scale = 1,
  }) {
    testWidgets('integrated RTL page-turn frames on $name', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final features = [
        if (book)
          ios
              ? _bookHinge
              : ui.DisplayFeature(
                  bounds: Rect.fromLTWH(size.width / 2, 0, 0, size.height),
                  type: ui.DisplayFeatureType.fold,
                  state: ui.DisplayFeatureState.postureHalfOpened,
                ),
        if (flatFold)
          ui.DisplayFeature(
            bounds: Rect.fromLTWH(size.width / 2, 0, 0, size.height),
            type: ui.DisplayFeatureType.fold,
            state: ui.DisplayFeatureState.postureFlat,
          ),
      ];
      final padding =
          insets ??
          (ipad
              ? const EdgeInsets.only(top: 24, bottom: 20)
              : EdgeInsets.only(bottom: ios ? 34 : 24));
      final ratio = QuranPageView.aspectRatioForMushaf(edition);
      final layout = ReaderLayout.resolve(
        size: size,
        padding: padding,
        preserveLegacyIPadPortrait: ipad,
        iosPhoneWidePortrait: ios && !ipad,
        displayFeatures: features,
        foldedCover: foldedCover,
        pageAspectRatio: ratio,
      );
      final paging = ReaderPaging(initialPage: 6, lastPage: 12);
      final visits = <int>[];
      final capture = GlobalKey();
      final palette = dark ? AppPalette.blackDark : AppPalette.emerald;
      String path(int page) => '${fixtures.path}/$edition-$page.png';
      final media = MediaQueryData(
        size: size,
        padding: padding,
        viewPadding: padding,
        displayFeatures: features,
      );
      await tester.pumpWidget(MaterialApp(home: const SizedBox()));
      final context = tester.element(find.byType(SizedBox).last);
      await tester.runAsync(
        () => Future.wait([
          for (var i = 1; i <= 12; i++)
            precacheImage(FileImage(File(path(i))), context),
        ]),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: palette.toThemeData().copyWith(
            platform: ios ? TargetPlatform.iOS : TargetPlatform.android,
          ),
          home: MediaQuery(
            data: media,
            child: RepaintBoundary(
              key: capture,
              child: Material(
                color: dark ? Colors.black : const Color(0xffe5e2db),
                child: Stack(
                  children: [
                    AdaptiveQuranPages(
                      paging: paging,
                      layout: layout,
                      singleScale: scale,
                      spreadScale: scale,
                      imagePath: path,
                      isDarkMode: dark,
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
                        expanded: false,
                        onToggle: () {},
                        palette: palette,
                        zoom: const SizedBox.shrink(),
                        actions: const [],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dock = find.byType(NavigationPullTab);
      final tab = tester.getRect(dock);
      final window = Offset.zero & size;
      for (final forward in [true, false]) {
        final direction = forward ? 'forward' : 'backward';
        final prefix = '$name/$direction';
        final initialPages = List.of(paging.visiblePages);
        Rect pageBounds(int page) =>
            tester.getRect(find.byKey(ValueKey('quran-page-$page')));
        final leaf = pageBounds(
          forward ? initialPages.last : initialPages.first,
        );
        final stationary = layout.singlePage
            ? null
            : pageBounds(
                forward ? initialPages.first : initialPages.last,
              ).intersect(window);
        final initial = await _frame(tester, capture, '$prefix-000');
        var previous = initial;
        final sign = forward ? 1 : -1;
        final gesture = await tester.startGesture(
          Offset(
            forward
                ? leaf.left + leaf.width * .12
                : leaf.right - leaf.width * .12,
            leaf.center.dy.clamp(30, size.height - 30),
          ),
        );
        // Cross touch slop before positioning the curl at each fraction.
        await gesture.moveBy(Offset(sign * 22.0, 0));
        await tester.pump();
        for (final fraction in [.25, .5, .75]) {
          await gesture.moveBy(
            Offset(sign * (fraction - paging.progress) * leaf.width, 0),
          );
          await tester.pump();
          expect(paging.progress, closeTo(fraction, .035));
          expect(paging.visiblePages, initialPages);
          expect(tester.getRect(dock), tab);
          final current = await _frame(
            tester,
            capture,
            '$prefix-${(fraction * 100).round().toString().padLeft(3, '0')}',
          );
          expect(
            _changedFraction(previous, current, window),
            greaterThan(.005),
            reason: 'each intermediate frame must visibly differ',
          );
          if (stationary != null && fraction == .25) {
            // Allow the resampling of fine print into the captured texture.
            // A slide would translate the print in this still-uncovered panel.
            final inside = stationary.deflate(
              stationary.size.shortestSide * .15,
            );
            expect(
              _changedFraction(initial, current, inside, tolerance: 64),
              lessThan(.035),
              reason: 'stationary leaf moved',
            );
          }
          final tabCenter = Rect.fromCenter(
            center: tab.center,
            width: tab.width * .35,
            height: tab.height * .35,
          );
          expect(
            _changedFraction(initial, current, tabCenter),
            0,
            reason: 'dock was covered',
          );
          if (book && ios) {
            expect(
              _changedFraction(initial, current, _bookHinge.bounds.deflate(1)),
              0,
              reason: 'physical gap painted over',
            );
          }
          previous = current;
        }
        await gesture.up();
        await tester.pumpAndSettle();
        final wanted = forward ? (layout.singlePage ? 7 : 8) : 6;
        expect(paging.visiblePages.first, wanted);
        expect(visits, forward ? [wanted] : [layout.singlePage ? 7 : 8, 6]);
        expect(tester.getRect(dock), tab);
        await _frame(tester, capture, '$prefix-100');
      }
      await tester.pumpWidget(const SizedBox());
      paging.dispose();
    });
  }

  profile(
    'iphone-portrait',
    const Size(390, 844),
    scale: .7,
    insets: const EdgeInsets.only(top: 47, bottom: 34),
  );
  profile(
    'ipad-mini-landscape',
    const Size(1133, 744),
    ipad: true,
    scale: .6,
    edition: 'madani',
  );
  profile('duo-book', const Size(951, 669), book: true, dark: true);
  if (_evidence.isNotEmpty) {
    profile(
      'ipad-mini-portrait',
      const Size(744, 1133),
      ipad: true,
      dark: true,
      edition: 'madani',
    );
    profile('duo-open-landscape', const Size(951, 669), scale: .85);
    profile('duo-open-portrait', const Size(669, 951), scale: .85);
    profile(
      'duo-folded',
      const Size(466, 678),
      foldedCover: true,
      insets: const EdgeInsets.only(right: 84, bottom: 34),
    );
    final config = jsonDecode(
      File('.github/scripts/samsung_foldable_profiles.json').readAsStringSync(),
    );
    for (final entry in (config['profiles'] as Map<String, dynamic>).entries) {
      Size logicalSize(String display) {
        final panel = entry.value['displays'][display];
        final density = panel['densityDpi'] / 160;
        return Size(
          (panel['width'] / density).roundToDouble(),
          (panel['height'] / density).roundToDouble(),
        );
      }

      final cover = logicalSize('cover');
      final inner = logicalSize('inner');
      final wide = Size(inner.longestSide, inner.shortestSide);
      final tall = Size(inner.shortestSide, inner.longestSide);
      profile('${entry.key}-folded', cover, ios: false, foldedCover: true);
      profile(
        '${entry.key}-portrait',
        tall,
        ios: false,
        flatFold: true,
        scale: .85,
      );
      profile(
        '${entry.key}-landscape',
        wide,
        ios: false,
        flatFold: true,
        dark: true,
        edition: 'madani',
      );
      profile('${entry.key}-book', inner, ios: false, book: true, scale: .6);
    }
  }
}
