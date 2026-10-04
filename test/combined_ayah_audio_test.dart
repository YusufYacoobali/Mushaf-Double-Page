import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/reader_audio_controls.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

void main() {
  for (final portrait in [true, false]) {
    testWidgets(
      'different selected ayah retains independent playback and ayah actions portrait=$portrait',
      (tester) async {
        tester.view.physicalSize = portrait
            ? const Size(320, 568)
            : const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final events = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  ReaderDock(
                    portrait: portrait,
                    expanded: true,
                    onToggle: () {},
                    palette: AppPalette.emerald,
                    zoom: const SizedBox(width: 32, height: 32),
                    actions: const [Icon(Icons.menu_book)],
                    contextControls: ReaderAudioControls(
                      portrait: portrait,
                      palette: AppPalette.emerald,
                      title: '2:7 · Selected',
                      reference: '2:10',
                      subtitle: 'Playing 2:10 · Reciter',
                      playing: true,
                      onPrevious: () => events.add('previous'),
                      onNext: () => events.add('next'),
                      onPlayPause: () => events.add('pause 2:10'),
                      onSettings: () {},
                      onStop: () => events.add('stop'),
                      selection: ReaderAudioSelection(
                        reference: '2:7',
                        bookmarked: false,
                        onBookmark: () => events.add('save 2:7'),
                        onTranslate: () => events.add('translate 2:7'),
                        onPlaySelected: () => events.add('play 2:7'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final tooltip in [
          'Pause',
          'Play selected ayah',
          'Save ayah',
          'Translate ayah',
          'Previous ayah',
          'Next ayah',
          'Stop audio',
        ]) {
          await tester.tap(find.byTooltip(tooltip));
          await tester.pumpAndSettle();
        }
        expect(events, [
          'pause 2:10',
          'play 2:7',
          'save 2:7',
          'translate 2:7',
          'previous',
          'next',
          'stop',
        ]);
        expect(find.byIcon(Icons.close_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
