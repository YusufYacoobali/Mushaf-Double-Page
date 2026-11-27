import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/navigator.dart';
import 'package:mushaf_two_page/utils/juz_list.dart';
import 'package:mushaf_two_page/utils/juz_mapper.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';
import 'package:mushaf_two_page/components/nav_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PageAyahIndex.load);

  testWidgets(
    'only the chevron expands quarters and the child supplies its surah',
    (tester) async {
      final jumps = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
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
      expect(find.text('Quarter 2 · ¼'), findsNothing);
      await tester.tap(find.byTooltip('Show quarters of Juz 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show quarters of Juz 1'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show quarters of Juz 2'), findsOneWidget);
      expect(find.text('Quarter 2 · ¼'), findsOneWidget);
      await tester.tap(find.text('Surah'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Juz'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Hide quarters of Juz 1'), findsOneWidget);
      await tester.tap(find.text('Quarter 2 · ¼'));
      await tester.pumpAndSettle();
      expect(jumps, [(2, 12)]);
    },
  );

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
