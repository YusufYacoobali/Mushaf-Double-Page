import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/bookmark_modal.dart';
import 'package:mushaf_two_page/components/translation_modal.dart';
import 'package:mushaf_two_page/pages/settings.dart';
import 'package:mushaf_two_page/progress/progress_page.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/translation_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final insets in [
    const FakeViewPadding(left: 59, bottom: 21),
    const FakeViewPadding(right: 59, bottom: 21),
    const FakeViewPadding(left: 59, right: 59, bottom: 21),
  ]) {
    testWidgets('landscape cutouts left=${insets.left} right=${insets.right}', (
      tester,
    ) async {
      const size = Size(844, 390);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        await (FontLoader('Inter')..addFont(
              rootBundle.load('assets/fonts/Inter-VariableFont_opsz,wght.ttf'),
            ))
            .load();
      });
      final theme = AppPalette.emerald.toThemeData();

      void expectSafe(Finder finder, {bool bottom = true}) {
        final bounds = tester.getRect(finder);
        expect(bounds.left, greaterThanOrEqualTo(insets.left));
        expect(bounds.right, lessThanOrEqualTo(size.width - insets.right));
        if (bottom) {
          expect(bounds.bottom, lessThanOrEqualTo(size.height - insets.bottom));
        }
      }

      for (final page in [const Settings(), const ProgressPage()]) {
        await tester.pumpWidget(MaterialApp(theme: theme, home: page));
        await tester.pumpAndSettle();
        expectSafe(find.byType(SingleChildScrollView));
        expect(tester.takeException(), isNull);
      }

      await tester.runAsync(() async {
        await PageAyahIndex.load();
        await TranslationManager.load();
      });
      // A cover page exercises the loaded translation layout without opening
      // native SQLite databases, which aren't available in widget tests.
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const TranslationModal(
            logicalPage: 1,
            mushaf: 'indopak_tajweed',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expectSafe(find.byType(ListView));
      expectSafe(find.byIcon(Icons.chevron_left_rounded));
      expectSafe(find.byIcon(Icons.chevron_right_rounded));
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expectSafe(find.text('Sources'));
      expectSafe(find.byType(SingleChildScrollView), bottom: false);
      Navigator.of(tester.element(find.text('Sources'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
      await tester.pumpAndSettle();
      expectSafe(find.text('Select Surah'));
      Navigator.of(tester.element(find.text('Select Surah'))).pop();
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => BookmarksModal.show(
                  context: context,
                  bookmarks: [],
                  isPortrait: false,
                  onAddBookmark: () {},
                  onRemoveBookmark: (_) {},
                  onJumpToBookmark: (_) {},
                ),
                child: const Text('Open bookmarks'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open bookmarks'));
      await tester.pumpAndSettle();
      expectSafe(find.text('Bookmarks'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
