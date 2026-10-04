import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/reader_audio_controls.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

void main() {
  for (final portrait in [true, false]) {
    for (final withContext in [false, true]) {
      testWidgets(
        'iPhone edge tab and safe controls portrait=$portrait context=$withContext',
        (tester) async {
          final size = portrait ? const Size(390, 844) : const Size(844, 390);
          final insets = portrait
              ? const FakeViewPadding(top: 47, bottom: 34)
              : const FakeViewPadding(left: 47, right: 47, bottom: 21);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.padding = insets;
          tester.view.viewPadding = insets;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
          var expanded = false;
          var navTaps = 0;
          var playTaps = 0;
          var pageSwipes = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppPalette.emerald.toThemeData().copyWith(
                platform: TargetPlatform.iOS,
              ),
              home: StatefulBuilder(
                builder: (context, refresh) => Scaffold(
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragEnd: (_) => pageSwipes++,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      ReaderDock(
                        portrait: portrait,
                        expanded: expanded,
                        onToggle: () => refresh(() => expanded = !expanded),
                        palette: AppPalette.emerald,
                        zoom: const SizedBox(width: 32, height: 32),
                        actions: [
                          IconButton(
                            tooltip: 'Reader settings',
                            onPressed: () => navTaps++,
                            icon: const Icon(Icons.settings),
                          ),
                        ],
                        contextControls: withContext
                            ? ReaderAudioControls(
                                portrait: portrait,
                                palette: AppPalette.emerald,
                                title: '2:7 · Al-Baqarah',
                                reference: '2:7',
                                subtitle: 'Reciter',
                                playing: true,
                                onPrevious: () {},
                                onPlayPause: () => playTaps++,
                                onNext: () {},
                                onStop: () {},
                                onSettings: () {},
                                selection: ReaderAudioSelection(
                                  reference: '2:7',
                                  bookmarked: false,
                                  onBookmark: () {},
                                  onTranslate: () {},
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final collapsed = tester.getRect(find.byType(NavigationPullTab));
          if (portrait) {
            expect(size.height - collapsed.bottom, closeTo(16, .01));
          } else {
            expect(size.width - collapsed.right, closeTo(4, .01));
            expect(
              collapsed.center.dy,
              closeTo((12 + size.height - insets.bottom) / 2, .01),
            );
            expect(
              collapsed.bottom,
              lessThanOrEqualTo(size.height - insets.bottom),
            );
          }
          await tester.dragFrom(const Offset(180, 180), const Offset(-100, 0));
          expect(pageSwipes, 1);
          await tester.tap(find.byTooltip('Open navigation'));
          await tester.pumpAndSettle();
          final outerPanel = tester.getRect(
            find.byKey(
              ValueKey(
                withContext
                    ? 'reader-context-panel'
                    : 'reader-navigation-panel',
              ),
            ),
          );
          if (portrait) {
            expect(
              size.height - outerPanel.bottom,
              closeTo(insets.bottom, .01),
            );
          } else {
            expect(size.width - outerPanel.right, closeTo(insets.right, .01));
            expect(
              tester.getCenter(find.byType(NavigationPullTab)).dy,
              closeTo(collapsed.center.dy, .01),
            );
          }
          await tester.tap(find.byTooltip('Reader settings'));
          expect(navTaps, 1);
          if (withContext) {
            await tester.tap(find.byTooltip('Pause'));
            expect(playTaps, 1);
          }
          await tester.tap(find.byTooltip('Collapse navigation'));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(NavigationPullTab)), collapsed);
          expect(find.byTooltip('Reader settings'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
