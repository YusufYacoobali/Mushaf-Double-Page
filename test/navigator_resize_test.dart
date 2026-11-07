import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/nav_tile.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/navigator.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(600, 840),
    const Size(900, 900),
    const Size(1200, 800),
    const Size(400, 280),
  ]) {
    testWidgets('navigator adapts width and text at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPalette.emerald.toThemeData(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => SurahJuzNavigator.show(
                  context: context,
                  mushaf: 'madani',
                  currentSurah: 98,
                  currentLogicalPage: 600,
                  onJumpToPage: (_) {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const ValueKey('surah-juz-panel')),
      );
      if (size == const Size(320, 568)) expect(panel.width, 320);
      if (size == const Size(844, 390)) {
        expect(panel.width, inInclusiveRange(420, 480));
      }
      expect(panel.width, lessThanOrEqualTo(size.width));
      expect(panel.right, size.width);
      final selected = find.byWidgetPredicate(
        (w) => w is NavTile && w.selected && w.number == 98,
      );
      expect(selected.hitTestable(), findsOneWidget);
      final title = find.descendant(
        of: selected,
        matching: find.text(tester.widget<NavTile>(selected).title),
      );
      expect(title, findsOneWidget);
      expect(tester.getRect(title).right, lessThan(panel.right - 24));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'resizing preserves a logical row anchor and independent tab positions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPalette.emerald.toThemeData(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => SurahJuzNavigator.show(
                  context: context,
                  mushaf: 'madani',
                  currentSurah: 60,
                  currentLogicalPage: 500,
                  onJumpToPage: (_) {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      int topRow() {
        final viewport = tester.getRect(find.byType(RawScrollbar));
        final rows = find.byType(NavTile).evaluate().where((e) {
          final r = tester.getRect(find.byWidget(e.widget));
          return r.bottom > viewport.top && r.top < viewport.bottom;
        }).toList();
        rows.sort(
          (a, b) => tester
              .getRect(find.byWidget(a.widget))
              .top
              .compareTo(tester.getRect(find.byWidget(b.widget)).top),
        );
        return (rows.first.widget as NavTile).number;
      }

      final surahAnchor = topRow();
      await tester.tap(find.text('Juz'));
      await tester.pumpAndSettle();
      final juzScroll = tester
          .widget<RawScrollbar>(find.byType(RawScrollbar))
          .controller!;
      juzScroll.jumpTo(500);
      await tester.pumpAndSettle();
      final juzAnchor = topRow();
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(topRow(), juzAnchor);
      await tester.tap(find.text('Surah'));
      await tester.pumpAndSettle();
      expect(topRow(), surahAnchor);
      await tester.tap(find.text('Juz'));
      await tester.pumpAndSettle();
      expect(topRow(), juzAnchor);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('open navigator fills the right hinge region with safe content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(950, 669);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(right: 20, bottom: 21),
            displayFeatures: const [
              DisplayFeature(
                bounds: Rect.fromLTWH(460, 0, 30, 669),
                type: DisplayFeatureType.hinge,
                state: DisplayFeatureState.postureHalfOpened,
              ),
            ],
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SurahJuzNavigator.show(
                context: context,
                mushaf: 'madani',
                onJumpToPage: (_) {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byKey(const ValueKey('surah-juz-panel')));
    expect(panel.left, greaterThanOrEqualTo(490));
    expect(panel.right, 950);
    expect(panel.bottom, 669);
    final content = tester.getRect(
      find.byKey(const ValueKey('surah-juz-content')),
    );
    expect(content.right, 930);
    expect(content.bottom, 648);
    expect(tester.takeException(), isNull);
  });
}
