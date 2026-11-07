import 'package:flutter/material.dart';
import '../pages/page_view.dart';
import '../utils/reader_layout.dart';
import '../utils/reader_paging.dart';

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

  @override
  Widget build(BuildContext context) {
    paging.configure(layout.pageMode);
    final generation = paging.generation;
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

    return PageView.builder(
      key: ValueKey('reader-pager-$generation'),
      controller: paging.controller,
      reverse: true,
      physics: const ClampingScrollPhysics(),
      itemCount: paging.pageCount,
      onPageChanged: (index) {
        if (paging.changed(index, generation)) {
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
                  ),
                ),
              ],
            )
          : spread(index),
    );
  }
}
