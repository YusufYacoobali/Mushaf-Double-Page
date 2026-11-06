import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/progress/daily_reading_card.dart';
import 'package:mushaf_two_page/progress/quran_reminder.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(900, 900),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'minimal popup retains hadith and reachable dismissal at $size dark=$dark',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var dismissed = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? AppPalette.blackDark : AppPalette.emerald)
                  .toThemeData(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.8)),
                child: child!,
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 480,
                        maxHeight: size.height * .5,
                      ),
                      child: DailyReadingCard(
                        streak: 5,
                        compact: true,
                        onClose: () => dismissed = true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(quranRecitationHadith), findsOneWidget);
          expect(find.text(quranRecitationHadithAttribution), findsOneWidget);
          expect(quranRecitationHadithAttribution, contains('804a'));
          expect(find.textContaining('A MOMENT'), findsNothing);
          expect(find.textContaining('CONNECTION'), findsNothing);
          expect(find.textContaining('Every return'), findsNothing);
          expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
          final dismiss = find.byTooltip('Dismiss welcome');
          expect(dismiss.hitTestable(), findsOneWidget);
          expect(
            tester.getSize(dismiss).shortestSide,
            greaterThanOrEqualTo(44),
          );
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -500),
          );
          await tester.pumpAndSettle();
          expect(dismiss.hitTestable(), findsOneWidget);
          await tester.tap(dismiss);
          expect(dismissed, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
