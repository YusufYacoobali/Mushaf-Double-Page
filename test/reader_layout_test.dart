import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/progress/journey_tracking.dart';

void main() {
  for (final mushaf in ['indopak_tajweed', 'madani']) {
    for (final sample in [
      (const Size(320, 568), ReaderPageMode.single, DockPlacement.bottom),
      (const Size(390, 844), ReaderPageMode.single, DockPlacement.bottom),
      (const Size(844, 390), ReaderPageMode.spread, DockPlacement.side),
      (const Size(600, 840), ReaderPageMode.single, DockPlacement.bottom),
      (const Size(900, 900), ReaderPageMode.spread, DockPlacement.bottom),
      (const Size(951, 669), ReaderPageMode.spread, DockPlacement.side),
      (const Size(1200, 800), ReaderPageMode.spread, DockPlacement.side),
      (const Size(340, 700), ReaderPageMode.single, DockPlacement.bottom),
      (const Size(500, 300), ReaderPageMode.single, DockPlacement.side),
    ]) {
      test('$mushaf adapts ${sample.$1} independently from dock placement', () {
        final layout = ReaderLayout.resolve(
          size: sample.$1,
          pageAspectRatio: QuranPageView.aspectRatioForMushaf(mushaf),
        );
        expect(layout.pageMode, sample.$2);
        expect(layout.dockPlacement, sample.$3);
        for (final rect in [...layout.pageRegions, layout.controlsRegion]) {
          expect((Offset.zero & sample.$1).contains(rect.topLeft), isTrue);
          expect(rect.right, lessThanOrEqualTo(sample.$1.width));
          expect(rect.bottom, lessThanOrEqualTo(sample.$1.height));
          expect(rect.isEmpty, isFalse);
        }
      });
    }
  }
  test('safe insets and available height can prevent an unreadable spread', () {
    expect(
      ReaderLayout.resolve(
        size: const Size(740, 900),
        padding: const EdgeInsets.symmetric(horizontal: 30),
      ).singlePage,
      isTrue,
    );
    expect(ReaderLayout.resolve(size: const Size(951, 220)).singlePage, isTrue);
    final safe = ReaderLayout.resolve(
      size: const Size(844, 390),
      padding: const EdgeInsets.fromLTRB(59, 0, 59, 21),
    );
    for (final r in safe.pageRegions) {
      expect(r.left, greaterThanOrEqualTo(59));
      expect(r.right, lessThanOrEqualTo(785));
      expect(r.bottom, lessThanOrEqualTo(369));
    }
  });
  test(
    'phone portrait pages use the full viewport beneath bottom control overlays',
    () {
      final compact = ReaderLayout.resolve(size: const Size(320, 568));
      expect(compact.singlePage, isTrue);
      expect(compact.bottomDock, isTrue);
      expect(compact.pageRegions.single, const Rect.fromLTWH(0, 0, 320, 568));
      final inset = ReaderLayout.resolve(
        size: const Size(320, 568),
        padding: const EdgeInsets.only(top: 20, bottom: 24),
      );
      expect(inset.pageRegions.single, const Rect.fromLTWH(0, 0, 320, 568));
      expect(inset.fullWidthPortrait, isTrue);
      // Wide portrait spreads still reserve their stable contextual-dock gutter.
      final spread = ReaderLayout.resolve(size: const Size(900, 900));
      expect(spread.singlePage, isFalse);
      expect(spread.pageRegions.every((r) => r.bottom == 758), isTrue);
    },
  );
  for (final type in [DisplayFeatureType.hinge, DisplayFeatureType.fold]) {
    test(
      'separating $type gives each page a region and keeps all controls clear',
      () {
        const hinge = Rect.fromLTWH(460, 0, 30, 669);
        final layout = ReaderLayout.resolve(
          size: const Size(950, 669),
          displayFeatures: [
            DisplayFeature(
              bounds: hinge,
              type: type,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
        );
        expect(layout.pageMode, ReaderPageMode.spread);
        expect(layout.spreadLayout, ReaderSpreadLayout.separateRegions);
        expect(layout.bottomDock, isTrue);
        expect(layout.pageRegions[0].right, lessThanOrEqualTo(460));
        expect(layout.pageRegions[1].left, greaterThanOrEqualTo(490));
        for (final r in [...layout.pageRegions, layout.controlsRegion]) {
          expect(r.overlaps(hinge), isFalse);
        }
      },
    );
  }
  test(
    'horizontal fold uses one screen; a flat zero-width fold is seamless',
    () {
      final tabletop = ReaderLayout.resolve(
        size: const Size(600, 840),
        displayFeatures: const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 410, 600, 20),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ],
      );
      expect(tabletop.singlePage, isTrue);
      expect(
        tabletop.controlsRegion.overlaps(const Rect.fromLTWH(0, 410, 600, 20)),
        isFalse,
      );
      final seamless = ReaderLayout.resolve(
        size: const Size(900, 900),
        displayFeatures: const [
          DisplayFeature(
            bounds: Rect.fromLTWH(450, 0, 0, 900),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureFlat,
          ),
        ],
      );
      expect(seamless.safeRegions.length, 1);
      expect(seamless.pageMode, ReaderPageMode.spread);
      expect(seamless.spreadLayout, ReaderSpreadLayout.widePortrait);
    },
  );
  test('interior cutouts cannot cover page text or controls', () {
    const cutout = Rect.fromLTWH(430, 0, 40, 80);
    final layout = ReaderLayout.resolve(
      size: const Size(900, 900),
      displayFeatures: const [
        DisplayFeature(
          bounds: cutout,
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
      ],
    );
    for (final r in [...layout.pageRegions, layout.controlsRegion]) {
      expect(r.overlaps(cutout), isFalse);
    }
  });
  test(
    'spread mapping includes every file once, with blank book boundaries',
    () {
      for (final last in [
        PageMapper.indopakLastFilePage,
        PageMapper.madaniLastFilePage,
      ]) {
        final pages = <int>[];
        for (var index = 0; index <= last ~/ 2; index++) {
          final focused = PageMapper.logicalFromPageIndex(index, false);
          pages.addAll(PageMapper.visiblePages(focused, false, last));
        }
        expect(pages, List.generate(last, (i) => i + 1));
        for (var page = 1; page <= last; page++) {
          expect(
            PageMapper.logicalFromPageIndex(
              PageMapper.pageIndexFromLogical(page, true),
              true,
            ),
            page,
          );
          expect(PageMapper.visiblePages(page, false, last), contains(page));
        }
      }
    },
  );
  test('a fold changes visible pages without adding a reading visit', () {
    final tracker = PageVisitTracker();
    expect(tracker.show(['madani:237']), 1);
    expect(tracker.show(['madani:236', 'madani:237'], count: false), 0);
    expect(tracker.show(['madani:236', 'madani:237']), 0);
    expect(tracker.show(['madani:237'], count: false), 0);
    expect(tracker.show(['madani:238']), 1);
  });
}
