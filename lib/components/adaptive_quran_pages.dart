import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../pages/page_view.dart';
import '../utils/reader_layout.dart';
import '../utils/reader_paging.dart';
import '../utils/audio_vertical_follower.dart';

/// Shared by the reader and resize regressions; old controller callbacks are
/// rejected by generation before they can change/persist a Quran page.
class AdaptiveQuranPages extends StatelessWidget {
  const AdaptiveQuranPages({
    super.key,
    required this.paging,
    required this.layout,
    required this.singleScale,
    required this.spreadScale,
    required this.imagePath,
    required this.isDarkMode,
    required this.aspectRatio,
    required this.highlightFor,
    required this.highlightColor,
    required this.onPageChanged,
    required this.onFocus,
    this.onTap,
    this.onBackgroundTap,
    this.verticalFollower,
    this.mushaf = 'indopak_tajweed',
  });
  final ReaderPaging paging;
  final ReaderLayout layout;
  final double singleScale, spreadScale, aspectRatio;
  final String Function(int) imagePath;
  final bool isDarkMode;
  final List<Rect> Function(int) highlightFor;
  final Color highlightColor;
  final ValueChanged<int> onPageChanged, onFocus;
  final void Function(int, double, double)? onTap;
  final VoidCallback? onBackgroundTap;
  final AudioVerticalFollower? verticalFollower;
  final String mushaf;

  @override
  Widget build(BuildContext context) {
    paging.configure(layout.pageMode);
    final generation = paging.generation;
    verticalFollower?.configureView(
      layoutIdentity: (
        generation,
        mushaf,
        layout.pageMode,
        layout.spreadLayout,
        layout.usableContentBounds,
        Object.hashAll(layout.pageRegions),
        MediaQuery.paddingOf(context),
        singleScale,
        spreadScale,
        aspectRatio,
      ),
      visiblePages: paging.visiblePages,
      settled: () {
        if (generation != paging.generation || !paging.controller.hasClients) {
          return false;
        }
        return !paging.controller.position.isScrollingNotifier.value &&
            ((paging.controller.page ?? -1) -
                        paging.indexFor(paging.focusedPage))
                    .abs() <
                .01;
      },
    );
    void focus(int page) {
      if (generation == paging.generation && paging.focus(page)) onFocus(page);
    }

    Widget spread(int index) {
      final centered =
          layout.spreadLayout == ReaderSpreadLayout.centeredLandscape;
      final content = QuranPageView.doublePage(
        spreadIndex: index,
        totalPages: paging.lastPage + 1,
        pageScale: spreadScale,
        imagePath: imagePath,
        isDarkMode: isDarkMode,
        aspectRatio: aspectRatio,
        highlightFor: highlightFor,
        highlightColor: highlightColor,
        onTap: onTap,
        onFocus: focus,
        onBackgroundTap: onBackgroundTap,
        pageRegions: centered ? null : layout.pageRegions,
        bookFirstPage: paging.book ? paging.firstPageAt(index) : null,
        verticalFollower: verticalFollower,
      );
      return centered
          ? Stack(
              children: [
                Positioned.fromRect(
                  rect: layout.usableContentBounds,
                  child: content,
                ),
              ],
            )
          : content;
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final follower = verticalFollower;
        if (notification.depth == 0 && follower != null) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            follower.userScroll(true);
          } else if (notification is ScrollEndNotification &&
              follower.userScrolling) {
            follower.userScroll(false);
          }
        }
        return false;
      },
      child: PageView.builder(
        key: ValueKey('reader-pager-$generation'),
        controller: paging.controller,
        reverse: true,
        pageSnapping: !paging.book,
        physics: paging.book
            ? _BookPagePhysics(
                panelWidth: layout.pageRegions
                    .map((r) => r.width)
                    .reduce(math.min),
                parent: const ClampingScrollPhysics(),
              )
            : const ClampingScrollPhysics(),
        itemCount: paging.pageCount,
        onPageChanged: (index) {
          if (paging.changed(index, generation)) {
            verticalFollower?.invalidate();
            onPageChanged(paging.focusedPage);
          }
        },
        itemBuilder: (context, index) => layout.singlePage
            ? Stack(
                children: [
                  Positioned.fromRect(
                    rect: layout.pageRegions.single,
                    child: QuranPageView.singlePage(
                      logicalPage: index + 1,
                      pageScale: singleScale,
                      imagePath: imagePath,
                      isDarkMode: isDarkMode,
                      aspectRatio: aspectRatio,
                      highlightRects: highlightFor(index + 1),
                      highlightColor: highlightColor,
                      onTap: onTap,
                      onFocus: focus,
                      onBackgroundTap: onBackgroundTap,
                      fullWidthPortrait: layout.fullWidthPortrait,
                      verticalFollower: verticalFollower,
                    ),
                  ),
                ],
              )
            : spread(index),
      ),
    );
  }
}

/// A deliberate drag within one leaf must turn the two-page book. Flutter's
/// default distance threshold is half the combined viewport, beyond one panel.
/// Keep its fling handling and spring; change only the slow-drag threshold.
class _BookPagePhysics extends PageScrollPhysics {
  const _BookPagePhysics({required this.panelWidth, super.parent});
  final double panelWidth;

  @override
  _BookPagePhysics applyTo(ScrollPhysics? ancestor) =>
      _BookPagePhysics(panelWidth: panelWidth, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);
    if (position is! ScrollPosition ||
        position.viewportDimension <= 0 ||
        position.outOfRange ||
        velocity.abs() > tolerance.velocity ||
        position.userScrollDirection == ScrollDirection.idle) {
      return super.createBallisticSimulation(position, velocity);
    }
    final threshold = (panelWidth / 2 / position.viewportDimension).clamp(
      0.0,
      .5,
    );
    final shift =
        (.5 - threshold) *
        (position.userScrollDirection == ScrollDirection.reverse ? 1 : -1);
    final target =
        ((position.pixels / position.viewportDimension + shift)
                    .roundToDouble() *
                position.viewportDimension)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    return target == position.pixels
        ? null
        : ScrollSpringSimulation(
            spring,
            position.pixels,
            target,
            velocity,
            tolerance: tolerance,
          );
  }
}
