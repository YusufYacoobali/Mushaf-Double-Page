// Flutter widget-rendering snapshots, not native device screenshots.
// RESPONSIVE_SCREENSHOTS=/tmp/v5-responsive-previews flutter test --no-pub tool/responsive_visual_smoke_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/navigator.dart';
import 'package:mushaf_two_page/progress/daily_reading_card.dart';

void main() {
  testWidgets(
    'render navigator and minimal reminder at representative widths',
    (tester) async {
      final output = Directory(
        Platform.environment['RESPONSIVE_SCREENSHOTS'] ??
            '/tmp/v5-responsive-previews',
      );
      await tester.runAsync(() async {
        await output.create(recursive: true);
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader('Inter')..addFont(
              rootBundle.load('assets/fonts/Inter-VariableFont_opsz,wght.ttf'),
            ))
            .load();
      });
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Future<void> save(GlobalKey key, String name) async {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${output.path}/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      for (final size in [
        const Size(320, 568),
        const Size(844, 390),
        const Size(900, 900),
      ]) {
        tester.view.physicalSize = size;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppPalette.emerald.toThemeData(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.4)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => SurahJuzNavigator.show(
                      context: context,
                      mushaf: 'madani',
                      currentSurah: 52,
                      currentLogicalPage: 530,
                      onJumpToPage: (_) {},
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await save(
          key,
          'navigator-${size.width.toInt()}x${size.height.toInt()}',
        );
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.physicalSize = const Size(320, 568);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppPalette.blackDark.toThemeData(),
            home: Scaffold(
              backgroundColor: Colors.black,
              body: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 480,
                      maxHeight: 284,
                    ),
                    child: DailyReadingCard(
                      streak: 5,
                      compact: true,
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await save(key, 'minimal-reminder-320x568');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
