import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/ios_display_regions.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const division = DisplayFeature(
    bounds: Rect.fromLTWH(460, 0, 30, 669),
    type: DisplayFeatureType.fold,
    state: DisplayFeatureState.postureHalfOpened,
  );
  test('iPad ignores Duo hints and preserves both orientation policies', () {
    for (final size in [const Size(744, 1133), const Size(1133, 744)]) {
      final original = ReaderLayout.resolve(
        size: size,
        preserveLegacyIPadPortrait: true,
      );
      final hinted = ReaderLayout.resolve(
        size: size,
        preserveLegacyIPadPortrait: true,
        iosPhoneWidePortrait: true,
        foldedCover: true,
      );
      expect(hinted.pageMode, original.pageMode);
      expect(hinted.pageRegions, original.pageRegions);
      expect(hinted.controlsRegion, original.controlsRegion);
      expect(hinted.fullWidthPortrait, original.fullWidthPortrait);
    }
  });
  test('folded cover stays single even in landscape', () {
    expect(
      ReaderLayout.resolve(
        size: const Size(678, 466),
        iosPhoneWidePortrait: true,
        foldedCover: true,
      ).pageMode,
      ReaderPageMode.single,
    );
  });
  test('flat portrait is single; flat landscape is the original spread', () {
    for (final size in [const Size(669, 951), const Size(951, 669)]) {
      final layout = ReaderLayout.resolve(
        size: size,
        iosPhoneWidePortrait: true,
        displayFeatures: [
          DisplayFeature(
            bounds: Rect.fromLTWH(size.width / 2, 0, 0, size.height),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureFlat,
          ),
        ],
      );
      expect(
        layout.pageMode,
        size.width < size.height
            ? ReaderPageMode.single
            : ReaderPageMode.spread,
      );
    }
  });
  test('cutouts alone cannot activate the book mode on an iPhone', () {
    final layout = ReaderLayout.resolve(
      size: const Size(951, 669),
      iosPhoneWidePortrait: true,
      displayFeatures: const [
        DisplayFeature(
          bounds: Rect.fromLTWH(460, 0, 30, 30),
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown,
        ),
      ],
    );
    expect(layout.pageMode, isNot(ReaderPageMode.dualScreenBook));
  });
  test('half-open book uses actual regions and keeps the hinge empty', () {
    final layout = ReaderLayout.resolve(
      size: const Size(950, 669),
      displayFeatures: const [division],
    );
    expect(layout.pageMode, ReaderPageMode.dualScreenBook);
    expect(layout.pageRegions[0].right, 460);
    expect(layout.pageRegions[1].left, 490);
    expect(layout.controlsRegion.overlaps(division.bounds), isFalse);
  });
  for (final page in [1, 4, 237, 624, 851]) {
    test(
      'book preserves focused $page, pairs forward, and advances by two',
      () {
        final paging = ReaderPaging(initialPage: page, lastPage: 851);
        paging.configure(ReaderPageMode.single);
        paging.attach(Object());
        paging.startDrag(page < 851 ? 1 : -1);
        final staleOperation = paging.operation;
        paging.settleDrag(commit: true);
        paging.configure(ReaderPageMode.dualScreenBook);
        expect(paging.visiblePages, [page, if (page < 851) page + 1]);
        expect(paging.pagesFor(page), paging.visiblePages);
        expect(paging.completeTurn(staleOperation), isFalse);
        if (page + 2 <= 851) {
          paging.startDrag(1);
          final operation = paging.operation;
          paging.settleDrag(commit: true);
          expect(paging.completeTurn(operation), isTrue);
          expect(paging.visiblePages, [
            page + 2,
            if (page + 3 <= 851) page + 3,
          ]);
        }
        final focused = paging.focusedPage;
        paging.configure(ReaderPageMode.single);
        expect(paging.visiblePages, [focused]);
        paging.dispose();
      },
    );
  }
  test(
    'both book pairings include every page once, without out-of-range leaves',
    () {
      for (final initial in [4, 237]) {
        for (final last in [624, 851]) {
          final paging = ReaderPaging(initialPage: initial, lastPage: last);
          paging.configure(ReaderPageMode.dualScreenBook);
          final pages = <int>[];
          for (var i = 0; i < paging.pageCount; i++) {
            final first = paging.firstPageAt(i);
            pages.addAll([
              for (var p = first; p < first + 2; p++)
                if (p >= 1 && p <= last) p,
            ]);
          }
          expect(pages, List.generate(last, (i) => i + 1));
          paging.dispose();
        }
      }
    },
  );
  test(
    'native frames retain logical points and reject stale rotation geometry',
    () {
      final event = IosDisplayRegions.fromEvent({
        'width': 950,
        'height': 669,
        'closed': false,
        'divisions': [
          {'left': 460, 'top': 0, 'width': 30, 'height': 669, 'active': true},
        ],
      });
      expect(
        event.forSize(const Size(950, 669)).single.bounds,
        division.bounds,
      );
      expect(event.forSize(const Size(950, 669)).single.state, division.state);
      expect(event.forSize(const Size(669, 950)), isEmpty);
      expect(IosDisplayRegions.fromEvent(null).features, isEmpty);
    },
  );
}
