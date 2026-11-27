import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/navigator.dart';
import 'package:mushaf_two_page/utils/juz_list.dart';
import 'package:mushaf_two_page/utils/juz_mapper.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';
import 'package:mushaf_two_page/components/nav_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PageAyahIndex.load);

  final panel = find.byKey(const ValueKey('surah-juz-panel'));

  Future<void> openPanel(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => SurahJuzNavigator.show(
              context: context,
              mushaf: 'madani',
              onJumpToPage: (_) {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
  }

  testWidgets('panel slides and fades over the opening and dismissal frames', (
    tester,
  ) async {
    await openPanel(tester);
    final width = tester.getSize(find.byType(Navigator)).width;
    final openLeft = width - tester.getSize(panel).width;
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: panel, matching: find.byType(FadeTransition)).first,
    );
    void expectFrame(double progress) {
      expect(fade.opacity.value, closeTo(progress, .001));
      expect(
        tester.getTopLeft(panel).dx,
        closeTo(openLeft + width * .18 * (1 - progress), .1),
      );
    }

    expectFrame(0);
    for (final t in [.25, .5, .75, 1.0]) {
      await tester.pump(const Duration(milliseconds: 75));
      expectFrame(Curves.easeInOut.transform(t));
    }
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10)); // Dismiss via the scrim.
    await tester.pump();
    expectFrame(1);
    for (final t in [.75, .5, .25]) {
      await tester.pump(const Duration(milliseconds: 95));
      expectFrame(Curves.easeOutCubic.transform(t));
    }
    await tester.pump(const Duration(milliseconds: 95));
    expectFrame(0);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
  });

  for (final features in [
    const FakeAccessibilityFeatures(disableAnimations: true),
    const FakeAccessibilityFeatures(accessibleNavigation: true),
  ]) {
    testWidgets('panel opens and dismisses immediately with $features', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = features;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openPanel(tester);
      final route = ModalRoute.of(tester.element(panel))!;
      expect(route.animation!.isCompleted, isTrue);
      expect(
        tester.getRect(panel).right,
        tester.getSize(find.byType(Navigator)).width,
      );
      expect(route.reverseTransitionDuration, Duration.zero);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(route.animation!.isDismissed, isTrue);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    });
  }

  testWidgets(
    'only the chevron expands quarters and the child supplies its surah',
    (tester) async {
      final jumps = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPalette.blackDark.toThemeData(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => SurahJuzNavigator.show(
                context: context,
                mushaf: 'indopak',
                onJumpToPage: (_) => fail('Lost surah'),
                onJumpToSurah: (s, p) => jumps.add((s, p)),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Juz'));
      await tester.pumpAndSettle();
      expect(find.text('¼ Juz'), findsNothing);
      await tester.tap(find.byTooltip('Show quarters of Juz 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show quarters of Juz 1'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show quarters of Juz 2'), findsOneWidget);
      for (final fraction in ['¼', '½', '¾']) {
        final row = find.widgetWithText(NavTile, '$fraction Juz');
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.text(fraction)),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Surah'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Juz'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide quarters of Juz 1'), findsOneWidget);
      await tester.tap(find.text('¼ Juz'));
      await tester.pumpAndSettle();
      expect(jumps, [(2, 12)]);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'quarter height, opacity and chevron follow motion settings: reduced=$reduced',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: JuzList(mushaf: 'indopak', onJump: (_) {}),
              ),
            ),
          ),
        );
        double nextRowY() => tester.getTopLeft(find.text('Juz 2')).dy;
        double arrowCosine() => tester
            .widget<Transform>(
              find.descendant(
                of: find.byTooltip('Hide quarters of Juz 1'),
                matching: find.byType(Transform),
              ),
            )
            .transform
            .storage[0];
        final closed = nextRowY();
        await tester.tap(find.byTooltip('Show quarters of Juz 1'));
        await tester.pump();
        if (!reduced) {
          expect(nextRowY(), closed);
          await tester.pump(const Duration(milliseconds: 100));
          expect(arrowCosine(), allOf(greaterThan(-1), lessThan(1)));
          final opacity = tester.widget<Opacity>(
            find
                .ancestor(
                  of: find.text('¼ Juz'),
                  matching: find.byType(Opacity),
                )
                .first,
          );
          expect(opacity.opacity, allOf(greaterThan(0), lessThan(1)));
        }
        final intermediate = nextRowY();
        await tester.pump(const Duration(milliseconds: 150));
        final open = nextRowY();
        expect(open, greaterThan(closed));
        expect(arrowCosine(), closeTo(-1, 0.001));
        expect(
          intermediate,
          reduced ? equals(open) : inExclusiveRange(closed, open),
        );
        await tester.tap(find.byTooltip('Hide quarters of Juz 1'));
        await tester.pump();
        if (!reduced) {
          expect(nextRowY(), open);
          await tester.pump(const Duration(milliseconds: 100));
          final closing = nextRowY();
          expect(closing, inExclusiveRange(closed, open));
          // A different section can open before the first has finished closing.
          await tester.tap(find.byTooltip('Show quarters of Juz 2'));
          await tester.pump();
          expect(nextRowY(), closing);
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byTooltip('Hide quarters of Juz 2'), findsOneWidget);
        } else {
          expect(find.text('¼ Juz'), findsNothing);
        }
        expect(nextRowY(), closed);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mushaf in ['indopak_tajweed', 'madani']) {
    for (final portrait in [true, false]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'current location opens visible $mushaf portrait=$portrait scale=$scale',
          (tester) async {
            tester.view.physicalSize = portrait
                ? const Size(390, 844)
                : const Size(844, 390);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final page = pageFromSurah(52, mushaf) + 1;
            final currentJuz = getJuzRanges(
              mushaf,
            ).lastWhere((j) => j.start <= page).juz;
            final jumps = <int>[];
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => SurahJuzNavigator.show(
                        context: context,
                        mushaf: mushaf,
                        currentLogicalPage: page,
                        currentSurah: 52,
                        onJumpToPage: jumps.add,
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            Finder selected(int number) => find.byWidgetPredicate(
              (w) => w is NavTile && w.selected && w.number == number,
            );
            expect(selected(52).hitTestable(), findsOneWidget);
            final viewport = tester.getRect(find.byType(RawScrollbar));
            expect(viewport.contains(tester.getCenter(selected(52))), isTrue);
            await tester.tap(find.text('Juz'));
            await tester.pumpAndSettle();
            expect(selected(currentJuz).hitTestable(), findsOneWidget);
            await tester.tap(selected(currentJuz));
            await tester.pumpAndSettle();
            expect(jumps, [pageFromJuz(currentJuz, mushaf)]);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('Juz segment accepts one tap beside its label', (tester) async {
    final jumps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SurahJuzNavigator.show(
                context: context,
                onJumpToPage: jumps.add,
                mushaf: 'indopak_tajweed',
              ),
              child: const Text('Open selector'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open selector'));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.text('Juz')) + const Offset(45, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(JuzList), findsOneWidget);
    await tester.tap(find.text('Juz 2'));
    await tester.pumpAndSettle();
    expect(jumps, [pageFromJuz(2, 'indopak_tajweed')]);
    expect(find.byType(JuzList), findsNothing);
  });

  for (final portrait in [true, false]) {
    for (final mushaf in ['indopak_tajweed', 'madani']) {
      testWidgets(
        'right scrollbar reaches both list ends portrait=$portrait mushaf=$mushaf',
        (tester) async {
          final size = portrait ? const Size(390, 844) : const Size(844, 390);
          final insets = portrait
              ? const FakeViewPadding(top: 47, bottom: 34)
              : const FakeViewPadding(left: 47, right: 47, bottom: 21);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = insets;
          tester.view.viewPadding = insets;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
          final jumps = <int>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: TargetPlatform.iOS),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => SurahJuzNavigator.show(
                        context: context,
                        onJumpToPage: jumps.add,
                        mushaf: mushaf,
                      ),
                      child: const Text('Open selector'),
                    ),
                  ),
                ),
              ),
            ),
          );
          Future<void> open() async {
            await tester.tap(find.text('Open selector'));
            await tester.pumpAndSettle();
          }

          Future<void> switchTo(String tab) async {
            // The entire segment must work, including space away from the label.
            await tester.tapAt(
              tester.getCenter(find.text(tab)) + const Offset(30, 0),
            );
            await tester.pumpAndSettle();
          }

          Future<double> dragToEnd() async {
            final finder = find.byType(RawScrollbar);
            final bar = tester.widget<RawScrollbar>(finder);
            expect(bar.thumbVisibility, isTrue);
            expect(bar.interactive, isTrue);
            final rect = tester.getRect(finder);
            final gesture = await tester.startGesture(
              Offset(rect.right - 7, rect.top + 22),
            );
            await tester.pump(const Duration(milliseconds: 50));
            await gesture.moveTo(Offset(rect.right - 7, rect.bottom - 8));
            await tester.pump();
            await gesture.up();
            await tester.pumpAndSettle();
            expect(bar.controller!.offset, greaterThan(500));
            expect(bar.controller!.position.extentAfter, lessThan(1));
            return bar.controller!.offset;
          }

          await open();
          final juzButton = tester.getRect(
            find
                .ancestor(of: find.text('Juz'), matching: find.byType(InkWell))
                .first,
          );
          expect(juzButton.height, 44);
          expect(
            juzButton.bottom,
            lessThanOrEqualTo(size.height - insets.bottom),
          );
          final surahOffset = await dragToEnd();
          await switchTo('Juz');
          expect(
            tester
                .widget<RawScrollbar>(find.byType(RawScrollbar))
                .controller!
                .offset,
            0,
          );
          await switchTo('Surah');
          expect(
            tester
                .widget<RawScrollbar>(find.byType(RawScrollbar))
                .controller!
                .offset,
            closeTo(surahOffset, 1),
          );
          final lastSurah = find.byWidgetPredicate(
            (w) => w is NavTile && w.number == 114,
          );
          await tester.tap(lastSurah);
          await tester.pumpAndSettle();
          expect(jumps, [pageFromSurah(114, mushaf)]);
          await open();
          await switchTo('Juz');
          await dragToEnd();
          await tester.tap(find.text('Juz 30'));
          await tester.pumpAndSettle();
          expect(jumps, [pageFromSurah(114, mushaf), pageFromJuz(30, mushaf)]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
