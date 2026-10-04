import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/bookmark_modal.dart';
import 'package:mushaf_two_page/utils/recent_surah_history.dart';

void main() {
  for (final portrait in [true, false]) {
    testWidgets(
      'last surah shortcut returns to its saved page portrait=$portrait',
      (tester) async {
        tester.view.physicalSize = portrait
            ? const Size(390, 844)
            : const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        final safe = portrait
            ? const FakeViewPadding(top: 47, bottom: 34)
            : const FakeViewPadding(left: 59, right: 59, bottom: 21);
        tester.view.padding = safe;
        tester.view.viewPadding = safe;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        SurahVisit? visited;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => BookmarksModal.show(
                    context: context,
                    bookmarks: [],
                    isPortrait: portrait,
                    onAddBookmark: () {},
                    onRemoveBookmark: (_) {},
                    onJumpToBookmark: (_) {},
                    previousSurah: const SurahVisit(surah: 2, page: 26),
                    onJumpToPreviousSurah: (visit) => visited = visit,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final shortcut = find.text('Last surah · Al-Baqarah');
        expect(shortcut, findsOneWidget);
        final rect = tester.getRect(shortcut);
        expect(rect.left, greaterThanOrEqualTo(safe.left));
        expect(
          rect.right,
          lessThanOrEqualTo(tester.view.physicalSize.width - safe.right),
        );
        expect(find.text('p. 23'), findsOneWidget);
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        expect(visited!.surah, 2);
        expect(visited!.page, 26);
        expect(find.text('Bookmarks'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
