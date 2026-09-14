import 'package:mushaf_two_page/components/reader_audio_controls.dart';
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
      for (final withAudio in [false, true]) {
        testWidgets(
          'reader controls fit $size dark=$dark audio=$withAudio and remain reachable',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final font = FontLoader('Inter')
              ..addFont(
                rootBundle.load(
                  'assets/fonts/Inter-VariableFont_opsz,wght.ttf',
                ),
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
            var audioTaps = 0;
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
                              padding: EdgeInsets.only(
                                right: portrait ? 0 : 95,
                              ),
                              child: portrait
                                  ? Image.asset(
                                      'assets/mushaf/indopak_tajweed_preview.png',
                                      fit: BoxFit.contain,
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                            audioControls: withAudio
                                ? ReaderAudioControls(
                                    portrait: portrait,
                                    palette: palette,
                                    title: 'Al-Baqarah:7',
                                    reference: '2:7',
                                    subtitle: 'Abdullah Al-Juhany · 2/10',
                                    playing: true,
                                    selection: ReaderAudioSelection(
                                      reference: '2:7',
                                      bookmarked: false,
                                      onBookmark: () => ayahTaps++,
                                      onTranslate: () => ayahTaps++,
                                    ),
                                    onPrevious: () => audioTaps++,
                                    onPlayPause: () => audioTaps++,
                                    onNext: () => audioTaps++,
                                    onSettings: () => audioTaps++,
                                  )
                                : null,
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
            final navRect = tester.getRect(
              find.byKey(const ValueKey('reader-navigation-panel')),
            );
            if (!withAudio) {
              final ayahRect = tester.getRect(find.byType(AyahActionBar));
              if (portrait) {
                expect(ayahRect.height, 38);
                expect(ayahRect.top, greaterThan(navRect.bottom));
              } else {
                expect(ayahRect.width, 38);
                expect(ayahRect.left, greaterThan(navRect.right));
              }
              expect(ayahRect.right, lessThanOrEqualTo(size.width));
              expect(ayahRect.bottom, lessThanOrEqualTo(size.height));
            } else {
              expect(find.byType(AyahActionBar), findsNothing);
              expect(find.byTooltip('Clear ayah selection'), findsNothing);
            }
            if (withAudio) {
              final audioRect = tester.getRect(
                find.byType(ReaderAudioControls),
              );
              expect(audioRect.left, greaterThanOrEqualTo(navRect.left));
              expect(audioRect.right, lessThanOrEqualTo(navRect.right));
              expect(audioRect.top, greaterThanOrEqualTo(navRect.top));
              expect(audioRect.bottom, lessThanOrEqualTo(navRect.bottom));
              final destinationRect = tester.getRect(find.byTooltip('Audio'));
              if (portrait) {
                expect(
                  audioRect.bottom,
                  lessThanOrEqualTo(destinationRect.top),
                );
              } else {
                expect(
                  audioRect.right,
                  lessThanOrEqualTo(destinationRect.left),
                );
              }
            }
            expect(
              tester
                  .widget<IconButton>(
                    find.widgetWithIcon(IconButton, Icons.add),
                  )
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
                  'build/reader-previews/${size.width.toInt()}-${dark ? 'dark' : 'ivory'}${withAudio ? '-audio' : ''}.png',
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
              if (!withAudio) 'Play ayah',
              'Save ayah',
              'Translate ayah',
              if (!withAudio) 'Clear ayah selection',
            ]) {
              await tester.tap(find.byTooltip(label));
              await tester.pumpAndSettle();
            }
            expect(ayahTaps, withAudio ? 2 : 4);
            if (withAudio) {
              for (final label in ['Previous ayah', 'Pause', 'Next ayah']) {
                await tester.tap(find.byTooltip(label));
                await tester.pumpAndSettle();
              }
              await tester.tap(
                find.text('Al-Baqarah:7').evaluate().isEmpty
                    ? find.byTooltip('Audio')
                    : find.text('Al-Baqarah:7'),
              );
              await tester.pumpAndSettle();
              expect(audioTaps, portrait ? 4 : 3);
            }
            {
              await tester.tap(find.byTooltip('Collapse navigation'));
              await tester.pumpAndSettle();
              expect(find.byTooltip('Audio'), findsNothing);
              expect(find.byType(AyahActionBar), findsNothing);
              expect(find.byType(ReaderAudioControls), findsNothing);
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
                    'build/reader-previews/${size.width.toInt()}-${dark ? 'dark' : 'ivory'}${withAudio ? '-audio' : ''}-collapsed.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              await tester.tap(find.byTooltip('Open navigation'));
              await tester.pumpAndSettle();
              expect(find.byTooltip('Audio'), findsOneWidget);
            }
          },
        );
      }
    }
  }
}
