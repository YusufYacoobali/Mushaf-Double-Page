import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/nav_bar_icon.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/components/ayah_action_bar.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(320, 568),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('reader controls fit $size dark=$dark and remain reachable', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final font = FontLoader('Inter')
          ..addFont(
            rootBundle.load('assets/fonts/Inter-VariableFont_opsz,wght.ttf'),
          );
        await tester.runAsync(() async {
          await font.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
        final portrait = size.height > size.width;
        final palette = dark ? AppPalette.blackDark : AppPalette.emerald;
        final boundaryKey = GlobalKey();
        var expanded = true;
        var taps = 0;
        var ayahTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: palette.toThemeData(),
            home: StatefulBuilder(
              builder: (context, refresh) => RepaintBoundary(
                key: boundaryKey,
                child: Scaffold(
                  backgroundColor: dark ? Colors.black : palette.scaffold,
                  body: Stack(
                    children: [
                      Center(
                        child: Padding(
                          padding: EdgeInsets.only(right: portrait ? 0 : 95),
                          child: portrait
                              ? Image.asset(
                                  'assets/mushaf/indopak_tajweed_preview.png',
                                  fit: BoxFit.contain,
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/mushaf/indopak_tajweed_preview.png',
                                      width: 250,
                                      fit: BoxFit.contain,
                                    ),
                                    Image.asset(
                                      'assets/mushaf/indopak_tajweed_preview.png',
                                      width: 250,
                                      fit: BoxFit.contain,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      ReaderDock(
                        ayahActions: AyahActionBar(
                          title: 'Al-Baqarah  2:7',
                          reference: '2:7',
                          vertical: !portrait,
                          bookmarked: false,
                          palette: palette,
                          onPlay: () => ayahTaps++,
                          onBookmark: () => ayahTaps++,
                          onTranslate: () => ayahTaps++,
                          onClose: () => ayahTaps++,
                        ),
                        portrait: portrait,
                        expanded: expanded,
                        onToggle: () => refresh(() => expanded = !expanded),
                        palette: palette,
                        zoom: ReaderZoom(
                          portrait: portrait,
                          palette: palette,
                          scale: 1.0,
                          minimum: .6,
                          onDecrease: () {},
                          onIncrease: () {},
                        ),
                        actions: [
                          for (final icon in [
                            Icons.headphones_rounded,
                            Icons.chat_outlined,
                            Icons.menu_book_outlined,
                            Icons.bookmarks_rounded,
                            Icons.settings,
                          ])
                            barIcon(
                              icon: icon,
                              onPressed: () => taps++,
                              palette: palette,
                              compact: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage('assets/mushaf/indopak_tajweed_preview.png'),
            boundaryKey.currentContext!,
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Audio'), findsNothing);
        expect(find.text('Quran'), findsNothing);
        final ayahRect = tester.getRect(find.byType(AyahActionBar));
        final navRect = tester.getRect(
          find.byKey(const ValueKey('reader-navigation-panel')),
        );
        if (portrait) {
          expect(ayahRect.height, 38);
          expect(ayahRect.top, greaterThan(navRect.bottom));
        } else {
          expect(ayahRect.width, 38);
          expect(ayahRect.left, greaterThan(navRect.right));
        }
        expect(ayahRect.right, lessThanOrEqualTo(size.width));
        expect(ayahRect.bottom, lessThanOrEqualTo(size.height));
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
              .onPressed,
          isNull,
        );
        if (const bool.fromEnvironment('READER_PREVIEWS')) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/reader-previews/${size.width.toInt()}-${dark ? 'dark' : 'ivory'}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        for (final label in [
          'Audio',
          'Translations, tafseer & notes',
          'Quran',
          'Bookmarks',
          'Settings',
        ]) {
          await tester.ensureVisible(find.byTooltip(label));
          await tester.tap(find.byTooltip(label));
          await tester.pumpAndSettle();
        }
        expect(taps, 5);
        for (final label in [
          'Play ayah',
          'Save ayah',
          'Translate ayah',
          'Clear ayah selection',
        ]) {
          await tester.tap(find.byTooltip(label));
          await tester.pumpAndSettle();
        }
        expect(ayahTaps, 4);
        {
          await tester.tap(find.byTooltip('Collapse navigation'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Audio'), findsNothing);
          expect(find.byType(AyahActionBar), findsNothing);
          if (const bool.fromEnvironment('READER_PREVIEWS')) {
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'build/reader-previews/${size.width.toInt()}-${dark ? 'dark' : 'ivory'}-collapsed.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(find.byTooltip('Open navigation'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Audio'), findsOneWidget);
        }
      });
    }
  }
}
