import 'package:mushaf_two_page/components/reader_audio_controls.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/nav_bar_icon.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(320, 568),
    const Size(360, 800), // Folded outer display with side controls.
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
            final cover = size == const Size(360, 800);
            final layout = ReaderLayout.resolve(
              size: size,
              androidCoverDock: cover,
            );
            final portrait = layout.bottomDock;
            Widget positionDock(Widget dock) =>
                cover ? ReaderDockOverlay(layout: layout, child: dock) : dock;
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
                                right: size.height > size.width ? 0 : 95,
                              ),
                              child: size.height > size.width
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
                          positionDock(
                            ReaderDock(
                              contextControls: ReaderAudioControls(
                                portrait: portrait,
                                palette: palette,
                                title: '2:7 · Al-Baqarah',
                                reference: '2:7',
                                subtitle: withAudio
                                    ? 'Abdullah Al-Juhany · 2/10'
                                    : 'Selected ayah',
                                playing: withAudio,
                                playbackActive: withAudio,
                                selection: ReaderAudioSelection(
                                  reference: '2:7',
                                  bookmarked: false,
                                  onBookmark: () => ayahTaps++,
                                  onTranslate: () => ayahTaps++,
                                ),
                                onPrevious: () => audioTaps++,
                                onPlayPause: () =>
                                    withAudio ? audioTaps++ : ayahTaps++,
                                onNext: () => audioTaps++,
                                onStop: withAudio ? () => audioTaps++ : null,
                                onSettings: () => audioTaps++,
                              ),
                              portrait: portrait,
                              expanded: expanded,
                              onToggle: () =>
                                  refresh(() => expanded = !expanded),
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
            final contextRect = tester.getRect(
              find.byType(ReaderAudioControls),
            );
            if (portrait) {
              expect(contextRect.height, 50);
              expect(contextRect.top, greaterThan(navRect.bottom));
              expect(navRect.height, 56);
            } else {
              expect(contextRect.width, 52);
              expect(contextRect.left, greaterThan(navRect.right));
              expect(navRect.width, 52);
            }
            expect(contextRect.right, lessThanOrEqualTo(size.width));
            expect(contextRect.bottom, lessThanOrEqualTo(size.height));
            expect(find.byTooltip('Clear ayah selection'), findsNothing);
            expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
            expect(
              tester
                  .widget<IconButton>(
                    find.widgetWithIcon(IconButton, Icons.stop_rounded),
                  )
                  .onPressed,
              withAudio ? isNotNull : isNull,
            );
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
            ]) {
              await tester.tap(find.byTooltip(label));
              await tester.pumpAndSettle();
            }
            expect(ayahTaps, withAudio ? 2 : 3);
            if (withAudio) {
              for (final label in [
                'Previous ayah',
                'Pause',
                'Next ayah',
                'Stop audio',
              ]) {
                await tester.tap(find.byTooltip(label));
                await tester.pumpAndSettle();
              }
              await tester.tap(
                find.byTooltip(
                  '2:7 · Al-Baqarah\nAbdullah Al-Juhany · 2/10\nAyah actions: 2:7',
                ),
              );
              await tester.pumpAndSettle();
              expect(audioTaps, 5);
            }
            {
              await tester.tap(find.byTooltip('Collapse navigation'));
              await tester.pumpAndSettle();
              expect(find.byTooltip('Audio'), findsNothing);
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
