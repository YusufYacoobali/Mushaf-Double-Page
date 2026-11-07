import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/reader_audio_controls.dart';
import 'package:mushaf_two_page/components/reader_dock.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/navigator.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';

// Frozen positioning baseline from v4 9cab9d5: ReaderDock was a direct child of
// the full-screen Stack. Its side tab is 22 x 72, right=4 when collapsed and
// right=max(6, safe.right)+50+(context ? 58 : 0) when expanded. Both states use
// the vertical band top=max(12, safe.top), bottom=max(12, safe.bottom).
void main() {
  for (final device in [
    (const Size(812, 375), 44.0, 446.6),
    (const Size(852, 393), 59.0, 468.6),
    (const Size(932, 430), 59.0, 480.0),
  ]) {
    for (final notchRight in [false, true]) {
      testWidgets('v4 iPhone dock ${device.$1} notchRight=$notchRight', (
        tester,
      ) async {
        final (size, notch, panelWidth) = device;
        final insets = FakeViewPadding(
          left: notchRight ? 0 : notch,
          right: notchRight ? notch : 0,
          bottom: 21,
        );
        configureView(tester, size, insets);
        final centerY = (12 + size.height - 21) / 2;
        for (final contextual in [false, true]) {
          var pauses = 0;
          await tester.pumpWidget(
            _DockScene(
              key: ValueKey(contextual),
              contextual: contextual,
              mushaf: contextual ? 'madani' : 'indopak_tajweed',
              onPlayPause: () => pauses++,
            ),
          );
          await tester.pumpAndSettle();
          final tab = find.byType(NavigationPullTab);
          final collapsed = tester.getRect(tab);
          expect(
            collapsed,
            Rect.fromCenter(
              center: Offset(size.width - 15, centerY),
              width: 22,
              height: 72,
            ),
          );
          await tester.tap(find.byTooltip('Open navigation'));
          await tester.pumpAndSettle();
          final right = math.max(6.0, insets.right);
          final extra = contextual ? 58.0 : 0.0;
          expect(
            tester.getRect(tab),
            Rect.fromLTWH(
              size.width - right - 72 - extra,
              centerY - 36,
              22,
              72,
            ),
          );
          expect(
            tester.getRect(
              find.byKey(const ValueKey('reader-navigation-panel')),
            ),
            Rect.fromLTRB(
              size.width - right - extra - 52,
              12,
              size.width - right - extra,
              size.height - 21,
            ),
          );
          if (contextual) {
            final contextPanel = tester.getRect(
              find.byKey(const ValueKey('reader-context-panel')),
            );
            expect(contextPanel.width, 52);
            expect(contextPanel.right, size.width - right);
            await tester.tap(find.byTooltip('Pause'));
            expect(pauses, 1);
          }

          await tester.tap(find.byTooltip('Surah navigator'));
          await tester.pumpAndSettle();
          void expectNavigator() {
            // Keep v5's adaptive width. Only the contents clear the notch and
            // home indicator; the Material background reaches screen edges.
            final panel = tester.getRect(
              find.byKey(const ValueKey('surah-juz-panel')),
            );
            expect(panel.left, closeTo(size.width - panelWidth, .001));
            expect(panel.right, size.width);
            expect(panel.top, 0);
            expect(panel.bottom, size.height);
            final content = tester.getRect(
              find.byKey(const ValueKey('surah-juz-content')),
            );
            expect(content.left, closeTo(panel.left, .001));
            expect(content.right, size.width - insets.right);
            expect(content.top, 12);
            expect(content.bottom, size.height - 21);
          }

          expectNavigator();
          await tester.tap(find.text('Juz'));
          await tester.pumpAndSettle();
          expectNavigator();
          await tester.tapAt(const Offset(8, 180));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('surah-juz-panel')), findsNothing);
          await tester.tap(find.byTooltip('Collapse navigation'));
          await tester.pumpAndSettle();
          expect(tester.getRect(tab), collapsed);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final sample in [
    (
      'Android',
      TargetPlatform.android,
      const Size(852, 393),
      <DisplayFeature>[],
    ),
    ('iPad', TargetPlatform.iOS, const Size(1024, 768), <DisplayFeature>[]),
    (
      'flat fold',
      TargetPlatform.iOS,
      const Size(932, 430),
      const [
        DisplayFeature(
          bounds: Rect.fromLTWH(466, 0, 0, 430),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
    ),
    (
      'hinge',
      TargetPlatform.iOS,
      const Size(932, 430),
      const [
        DisplayFeature(
          bounds: Rect.fromLTWH(451, 0, 30, 430),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ],
    ),
  ]) {
    testWidgets('${sample.$1} keeps its adaptive dock region', (tester) async {
      configureView(
        tester,
        sample.$3,
        const FakeViewPadding(right: 44, bottom: 21),
      );
      late ReaderLayout layout;
      await tester.pumpWidget(
        _DockScene(
          platform: sample.$2,
          features: sample.$4,
          onLayout: (value) => layout = value,
        ),
      );
      await tester.pumpAndSettle();
      final region = layout.controlsRegion;
      final collapsed = tester.getRect(find.byType(NavigationPullTab));
      if (layout.bottomDock) {
        expect(collapsed.bottom, region.bottom - 16);
        expect(collapsed.center.dx, region.center.dx);
        expect(collapsed.overlaps(sample.$4.single.bounds), isFalse);
      } else {
        expect(collapsed.right, region.right - 4);
        expect(collapsed.center.dy, region.center.dy);
      }
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
      final panel = tester.getRect(
        find.byKey(const ValueKey('reader-navigation-panel')),
      );
      if (layout.bottomDock) {
        expect(panel.bottom, region.bottom - 16);
        expect(panel.overlaps(sample.$4.single.bounds), isFalse);
      } else {
        expect(panel.right, region.right - 6);
        expect(panel.top, region.top + 12);
        expect(panel.bottom, region.bottom - 12);
      }
      expect(tester.takeException(), isNull);
    });
  }
}

void configureView(WidgetTester tester, Size size, FakeViewPadding insets) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = insets;
  tester.view.viewPadding = insets;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

/// The production main.dart composition, including the overlay's coordinate
/// system and the unchanged ReaderDock animations and context controls.
class _DockScene extends StatefulWidget {
  const _DockScene({
    super.key,
    this.contextual = false,
    this.mushaf = 'madani',
    this.platform = TargetPlatform.iOS,
    this.features = const [],
    this.onPlayPause,
    this.onLayout,
  });
  final bool contextual;
  final String mushaf;
  final TargetPlatform platform;
  final List<DisplayFeature> features;
  final VoidCallback? onPlayPause;
  final ValueChanged<ReaderLayout>? onLayout;
  @override
  State<_DockScene> createState() => _DockSceneState();
}

class _DockSceneState extends State<_DockScene> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppPalette.emerald.toThemeData().copyWith(platform: widget.platform),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(displayFeatures: widget.features),
      child: child!,
    ),
    home: Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = ReaderLayout.resolve(
            size: constraints.biggest,
            padding: MediaQuery.paddingOf(context),
            displayFeatures: widget.features,
          );
          widget.onLayout?.call(layout);
          return Stack(
            children: [
              const Positioned.fill(child: SizedBox.expand()),
              ReaderDockOverlay(
                layout: layout,
                child: ReaderDock(
                  placement: layout.dockPlacement,
                  expanded: expanded,
                  onToggle: () => setState(() => expanded = !expanded),
                  palette: AppPalette.emerald,
                  zoom: ReaderZoom(
                    portrait: layout.bottomDock,
                    palette: AppPalette.emerald,
                    scale: .7,
                    minimum: .6,
                    onDecrease: () {},
                    onIncrease: () {},
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Surah navigator',
                      icon: const Icon(Icons.menu_book),
                      onPressed: () => SurahJuzNavigator.show(
                        context: context,
                        onJumpToPage: (_) {},
                        mushaf: widget.mushaf,
                      ),
                    ),
                  ],
                  contextControls: widget.contextual
                      ? ReaderAudioControls(
                          portrait: layout.bottomDock,
                          palette: AppPalette.emerald,
                          title: 'Al-Baqarah',
                          reference: '2:7',
                          subtitle: 'Reciter',
                          playing: true,
                          onPrevious: () {},
                          onNext: () {},
                          onPlayPause: widget.onPlayPause ?? () {},
                          onSettings: () {},
                          onStop: () {},
                        )
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
