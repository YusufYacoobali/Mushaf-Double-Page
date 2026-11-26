import 'package:flutter/material.dart';
import 'quran_page_turn_view.dart';
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
    final geometry = (
      mushaf,
      MediaQuery.sizeOf(context),
      MediaQuery.paddingOf(context),
      layout.pageMode,
      layout.spreadLayout,
      layout.sizing,
      layout.centerShortLandscapeSpread,
      layout.usableContentBounds,
      Object.hashAll(layout.pageRegions),
      Object.hashAll(layout.safeRegions),
      singleScale,
      spreadScale,
      aspectRatio,
    );

    return QuranPageTurnView(
      paging: paging,
      layout: layout,
      layoutIdentity: (geometry, isDarkMode),
      isDarkMode: isDarkMode,
      onUserTurn: verticalFollower?.userScroll,
      onPageChanged: (page) {
        verticalFollower?.invalidate();
        onPageChanged(page);
      },
      buildSurface: (index, active, wrapLeaf) {
        final generation = paging.generation;
        final follower = active ? verticalFollower : null;
        follower?.configureView(
          layoutIdentity: (generation, geometry),
          visiblePages: paging.visiblePages,
          settled: () => generation == paging.generation && paging.settled,
        );
        void focus(int page) {
          if (generation == paging.generation && paging.focus(page)) {
            onFocus(page);
          }
        }

        if (layout.singlePage) {
          final page = paging.firstPageAt(index);
          return Stack(
            children: [
              Positioned.fromRect(
                rect: layout.pageRegions.single,
                child: QuranPageView.singlePage(
                  logicalPage: page,
                  pageScale: singleScale,
                  imagePath: imagePath,
                  isDarkMode: isDarkMode,
                  aspectRatio: aspectRatio,
                  highlightRects: highlightFor(page),
                  highlightColor: highlightColor,
                  onTap: active ? onTap : null,
                  onFocus: active ? focus : null,
                  onBackgroundTap: active ? onBackgroundTap : null,
                  fullWidthPortrait:
                      layout.sizing == ReaderPageSizing.portraitHeight,
                  viewportBounds: layout.usableContentBounds,
                  fitToViewport: layout.sizing == ReaderPageSizing.regionFit,
                  verticalFollower: follower,
                  wrapLeaf: wrapLeaf,
                ),
              ),
            ],
          );
        }

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
          onTap: active ? onTap : null,
          onFocus: active ? focus : null,
          onBackgroundTap: active ? onBackgroundTap : null,
          pageRegions: centered ? null : layout.pageRegions,
          centerShortLandscapeSpread: layout.centerShortLandscapeSpread,
          bookFirstPage: paging.book ? paging.firstPageAt(index) : null,
          fitToViewport: layout.sizing == ReaderPageSizing.regionFit,
          verticalFollower: follower,
          wrapLeaf: wrapLeaf,
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
      },
    );
  }
}
