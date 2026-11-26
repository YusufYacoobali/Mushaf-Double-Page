import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/components/bookmark_modal.dart';
import 'package:mushaf_two_page/components/audio_modal.dart';
import 'package:mushaf_two_page/components/translation_modal.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/pages/settings.dart';
import 'package:mushaf_two_page/pages/tasbeeh.dart';
import 'package:mushaf_two_page/progress/progress_page.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/tasbeeh_store.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/translation_manager.dart';
import 'audio_test_fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Widget mediaBuilder(BuildContext context, Widget? child) {
    final data = MediaQuery.of(context);
    final wide = data.size.width >= 900;
    return MediaQuery(
      data: data.copyWith(
        textScaler: TextScaler.linear(1.4),
        displayFeatures: wide
            ? const [
                DisplayFeature(
                  bounds: Rect.fromLTWH(460, 0, 30, 669),
                  type: DisplayFeatureType.hinge,
                  state: DisplayFeatureState.postureHalfOpened,
                ),
              ]
            : [],
      ),
      child: child!,
    );
  }

  testWidgets(
    'secondary screens stay in a safe region and keep their state through folding',
    (tester) async {
      tester.view.physicalSize = const Size(950, 669);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await PageAyahIndex.load();
        await TranslationManager.load();
      });
      final store = TasbeehStore();
      await store.restore();
      final pages = [
        const Settings(),
        const ProgressPage(),
        TasbeehPage(store: store),
        const TranslationModal(logicalPage: 1, mushaf: 'madani'),
      ];
      for (final page in pages) {
        tester.view.physicalSize = const Size(950, 669);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppPalette.emerald.toThemeData(),
            builder: mediaBuilder,
            home: page,
          ),
        );
        await tester.pumpAndSettle();
        final scaffold = tester.getRect(find.byType(Scaffold));
        expect(scaffold.right, lessThanOrEqualTo(460));
        expect(
          scaffold.overlaps(const Rect.fromLTWH(460, 0, 30, 669)),
          isFalse,
        );
        tester.view.physicalSize = const Size(320, 568);
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(Scaffold)).width, 320);
        expect(
          tester.takeException(),
          isNull,
          reason: page.runtimeType.toString(),
        );
      }
      await tester.pumpWidget(const SizedBox());
      await store.flush();
      store.dispose();
    },
  );
  testWidgets(
    'open bookmark and audio sheets resize within the current sub-screen',
    (tester) async {
      tester.view.physicalSize = const Size(950, 669);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = QuranAudioController.forTesting(
        player: FakePlayer(),
        repository: ControlledRepository(),
        resolveIntroduction: fixtureIntroduction,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppPalette.emerald.toThemeData(),
          builder: mediaBuilder,
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => BookmarksModal.show(
                      context: context,
                      bookmarks: [],
                      isPortrait: false,
                      onAddBookmark: () {},
                      onRemoveBookmark: (_) {},
                      onJumpToBookmark: (_) {},
                    ),
                    child: const Text('Bookmarks'),
                  ),
                  TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) =>
                          AudioModal(initialSurah: 112, controller: controller),
                    ),
                    child: const Text('Audio'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final label in ['Bookmarks', 'Audio']) {
        tester.view.physicalSize = const Size(950, 669);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
        var sheet = tester.getRect(find.byType(BottomSheet));
        expect(sheet.right, lessThanOrEqualTo(460));
        expect(sheet.width, lessThanOrEqualTo(640));
        tester.view.physicalSize = const Size(320, 568);
        await tester.pumpAndSettle();
        sheet = tester.getRect(find.byType(BottomSheet));
        expect(sheet.left, greaterThanOrEqualTo(0));
        expect(sheet.right, lessThanOrEqualTo(320));
        expect(sheet.bottom, lessThanOrEqualTo(568));
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
