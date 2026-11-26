import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/pages/tasbeeh.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/tasbeeh_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Inter')..addFont(
          rootBundle.load('assets/fonts/Inter-VariableFont_opsz,wght.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final sample in [
    (const Size(390, 844), const FakeViewPadding(bottom: 24)),
    (const Size(320, 568), const FakeViewPadding(bottom: 48)),
    (const Size(844, 390), const FakeViewPadding(right: 48, bottom: 24)),
  ]) {
    for (final customCount in [0, 20]) {
      testWidgets(
        'dhikr sheets clear navigation bars ${sample.$1} bottom=${sample.$2.bottom} right=${sample.$2.right} custom=$customCount',
        (tester) async {
          final size = sample.$1, insets = sample.$2;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.padding = insets;
          tester.view.viewPadding = insets;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
          SharedPreferences.setMockInitialValues({});
          final store = TasbeehStore();
          await store.restore();
          for (var i = 0; i < customCount; i++) {
            store.addCustom('Saved dhikr $i');
          }
          store.select('subhanallah');
          store.increment();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppPalette.emerald.toThemeData().copyWith(
                platform: TargetPlatform.android,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: TasbeehPage(store: store),
            ),
          );
          await tester.pumpAndSettle();
          Finder tileFor(Finder label) =>
              find.ancestor(of: label, matching: find.byType(ListTile));

          void expectSafe(Finder label) {
            final tile = tileFor(label);
            expect(tile.hitTestable(), findsOneWidget);
            final rect = tester.getRect(tile);
            expect(rect.bottom, lessThanOrEqualTo(size.height - insets.bottom));
            expect(rect.right, lessThanOrEqualTo(size.width - insets.right));
            expect(rect.left, greaterThanOrEqualTo(insets.left));
          }

          await tester.tap(find.byTooltip('Manage dhikr'));
          await tester.pumpAndSettle();
          final add = find.text('Add custom dhikr');
          await tester.ensureVisible(tileFor(add));
          await tester.pumpAndSettle();
          expectSafe(add);
          expect(store.count, BigInt.one);
          await tester.tap(add);
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(store.count, BigInt.one);
          Navigator.of(tester.element(add)).pop();
          await tester.pumpAndSettle();
          // The selector's ListView already applies its automatic bottom padding.
          await tester.tap(find.text('SubhanAllah'));
          await tester.pumpAndSettle();
          final custom = find.text('Custom dhikr');
          await tester.scrollUntilVisible(
            tileFor(custom),
            250,
            scrollable: find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expectSafe(custom);
          await tester.tap(custom);
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(store.count, BigInt.one);
          expect(store.dhikrs.where((d) => d.custom).length, customCount);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await store.flush();
          store.dispose();
        },
      );
    }
  }
}
