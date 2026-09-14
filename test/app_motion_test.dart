import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/ayah_action_bar.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/components/reader_audio_controls.dart';
import 'package:mushaf_two_page/utils/app_motion.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

void main() {
  for (final portrait in [true, false]) {
    testWidgets(
      'dock reverses mid-flight and leaves page swipes working portrait=$portrait',
      (tester) async {
        tester.view.physicalSize = portrait
            ? const Size(390, 844)
            : const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var expanded = true;
        var selected = true;
        var hasAudio = true;
        var swipes = 0;
        late StateSetter update;
        const palette = AppPalette.emerald;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, refresh) {
                update = refresh;
                return Scaffold(
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragEnd: (_) => swipes++,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      ReaderDock(
                        audioControls: hasAudio
                            ? ReaderAudioControls(
                                portrait: portrait,
                                palette: palette,
                                title: 'Al-Baqarah:7',
                                reference: '2:7',
                                subtitle: 'Reciter · 2/10',
                                playing: true,
                                onPrevious: () {},
                                onPlayPause: () {},
                                onNext: () {},
                                onSettings: () {},
                              )
                            : null,
                        portrait: portrait,
                        expanded: expanded,
                        onToggle: () => refresh(() => expanded = !expanded),
                        palette: palette,
                        zoom: const SizedBox(width: 32, height: 32),
                        actions: [
                          IconButton(
                            tooltip: 'Destination',
                            onPressed: () {},
                            icon: const Icon(Icons.settings),
                          ),
                        ],
                        ayahActions: selected
                            ? AyahActionBar(
                                title: 'Al-Baqarah 2:7',
                                reference: '2:7',
                                vertical: !portrait,
                                bookmarked: false,
                                palette: palette,
                                onPlay: () {},
                                onBookmark: () {},
                                onTranslate: () {},
                                onClose: () => refresh(() => selected = false),
                              )
                            : null,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Collapse navigation'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(find.byTooltip('Destination'), findsOneWidget);
        await tester.dragFrom(const Offset(200, 170), const Offset(-100, 0));
        expect(swipes, 1);
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        update(() {
          selected = false;
          expanded = false;
          hasAudio = false;
        });
        await tester.pumpAndSettle();
        expect(find.byType(AyahActionBar), findsNothing);
        expect(find.byTooltip('Destination'), findsNothing);
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Destination'), findsOneWidget);
        expect(find.byType(ReaderAudioControls), findsNothing);
        update(() {
          selected = true;
          hasAudio = true;
        });
        await tester.pumpAndSettle();
        expect(find.byType(ReaderAudioControls), findsOneWidget);
        expect(find.byType(AyahActionBar), findsNothing);
        update(() => hasAudio = false);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Clear ayah selection'));
        await tester.pump();
        expect(find.byType(AyahActionBar), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.byType(AyahActionBar), findsNothing);
        update(() => hasAudio = false);
        await tester.pumpAndSettle();
        expect(find.byType(ReaderAudioControls), findsNothing);
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets('outgoing overlays cannot intercept taps during their fade', (
    tester,
  ) async {
    var visible = true;
    var taps = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, refresh) {
            update = refresh;
            return Scaffold(
              body: Center(
                child: MotionSwitcher(
                  child: visible
                      ? TextButton(
                          key: const ValueKey('action'),
                          onPressed: () => taps++,
                          child: const Text('Action'),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty')),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final position = tester.getCenter(find.text('Action'));
    update(() => visible = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(position);
    expect(taps, 0);
    await tester.pumpAndSettle();
    expect(find.text('Action'), findsNothing);
  });

  testWidgets('press cancellation restores the button without activating it', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressMotion(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Button'),
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Button')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .93);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(taps, 0);
  });

  testWidgets(
    'page transitions retain pop results and reduced motion removes movement',
    (tester) async {
      for (final reduced in [false, true]) {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            theme: AppPalette.emerald.toThemeData().copyWith(
              platform: TargetPlatform.android,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: const Scaffold(body: Text('Reader')),
          ),
        );
        final result = navigator.currentState!.push(
          MaterialPageRoute<String>(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Settings destination')),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final destination = find.text('Settings destination');
        expect(destination, findsOneWidget);
        final transforms = find.ancestor(
          of: destination,
          matching: find.byType(Transform),
        );
        expect(transforms, reduced ? findsNothing : findsWidgets);
        await tester.pumpAndSettle();
        navigator.currentState!.pop('saved');
        await tester.pumpAndSettle();
        expect(await result, 'saved');
        expect(find.text('Reader'), findsOneWidget);
      }
    },
  );
}
