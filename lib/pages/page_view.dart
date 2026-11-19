import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/cache.dart';
import '../utils/audio_vertical_follower.dart';
import '../components/audio_vertical_viewport.dart';
import '../components/quran_page_turn_view.dart';

class QuranPageView {
  // Spread/adaptive pages use their printed image's native aspect ratio.
  // Phone portrait pages retain v4's full-width, height-only toolbar zoom;
  // highlights and taps share that stretched surface's normalized coordinates.
  static const double pageAspectRatio = 721 / 1058;
  static const double madaniPageAspectRatio = 2096 / 3008;

  static double aspectRatioForMushaf(String mushaf) =>
      mushaf == 'madani' ? madaniPageAspectRatio : pageAspectRatio;

  static const double minPageScalePortrait = 0.7;
  static const double maxPageScalePortrait = 1.0;
  static const double minPageScaleLandscape = 0.60;
  static const double maxPageScaleLandscape = 1.0;

  static const ColorFilter invertFilter = ColorFilter.matrix([
    -1,
    0,
    0,
    0,
    255,
    0,
    -1,
    0,
    0,
    255,
    0,
    0,
    -1,
    0,
    255,
    0,
    0,
    0,
    1,
    0,
  ]);

  static Widget singlePage({
    required int logicalPage,
    required double pageScale,
    required String Function(int) imagePath,
    required bool isDarkMode,
    double aspectRatio = pageAspectRatio,
    List<Rect> highlightRects = const [],
    Color highlightColor = const Color(0x5580643B),
    void Function(int logicalPage, double nx, double ny)? onTap,
    VoidCallback? onBackgroundTap,
    TransformationController? transformationController,
    AudioVerticalFollower? verticalFollower,
    ValueChanged<int>? onFocus,
    Widget Function(int, Widget)? wrapLeaf,
    bool fullWidthPortrait = true,
    Rect? viewportBounds,
    bool fitToViewport = false,
  }) {
    final clamped = pageScale.clamp(minPageScalePortrait, maxPageScalePortrait);
    final path = imagePath(logicalPage);
    Widget image = QuranPageCache.getPage(path);

    if (isDarkMode) {
      image = ColorFiltered(colorFilter: invertFilter, child: image);
    }

    return AudioVerticalViewport(
      pages: [logicalPage],
      follower: verticalFollower,
      transformed: true,
      transformationController: transformationController,
      transformIdentity: (
        clamped,
        aspectRatio,
        fullWidthPortrait,
        fitToViewport,
        viewportBounds,
      ),
      builder: (viewport) => _BackgroundTapListener(
        pageSurfaceKey: viewport.pageKey(logicalPage),
        onBackgroundTap: onBackgroundTap,
        builder: (pageSurfaceKey) => LayoutBuilder(
          builder: (context, constraints) {
            // v4 portrait zoom changes height only; phone pages always fill the
            // viewport width. Adaptive single-page regions keep their native ratio.
            final width = fitToViewport
                ? math.min(
                        constraints.maxWidth,
                        constraints.maxHeight * aspectRatio,
                      ) *
                      clamped
                : fullWidthPortrait
                ? constraints.maxWidth
                : math.min(
                    constraints.maxWidth,
                    constraints.maxHeight * clamped * aspectRatio,
                  );
            final leaf = SizedBox(
              key: ValueKey('quran-page-$logicalPage'),
              width: width,
              height: fullWidthPortrait
                  ? constraints.maxHeight * clamped
                  : width / aspectRatio,
              child: _PageContent(
                surfaceKey: pageSurfaceKey,
                image: fullWidthPortrait
                    ? FittedBox(fit: BoxFit.fill, child: image)
                    : image,
                aspectRatio: aspectRatio,
                stretchToFit: true,
                highlightRects: highlightRects,
                highlightColor: highlightColor,
                onTap: onTap == null && onFocus == null
                    ? null
                    : (nx, ny) {
                        onFocus?.call(logicalPage);
                        onTap?.call(logicalPage, nx, ny);
                      },
              ),
            );
            return SizedBox.expand(
              child: InteractiveViewer(
                key: ValueKey(clamped),
                transformationController: viewport.transform,
                onInteractionStart: (_) => QuranPageTurnView.singlePageGesture(
                  context,
                  viewport.transform,
                ),
                onInteractionUpdate: (_) => QuranPageTurnView.singlePageGesture(
                  context,
                  viewport.transform,
                ),
                constrained: false,
                panEnabled:
                    viewport.verticalPanEnabled &&
                    QuranPageTurnView.allowVerticalPan(context),
                panAxis: PanAxis.vertical,
                boundaryMargin: viewport.boundaryMargin,
                minScale: 1,
                maxScale: maxPageScalePortrait / clamped,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Center(
                    child: wrapLeaf?.call(logicalPage, leaf) ?? leaf,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static Widget doublePage({
    required int spreadIndex,
    required String Function(int) imagePath,
    required int totalPages,
    required double pageScale,
    required bool isDarkMode,
    double aspectRatio = pageAspectRatio,
    List<Rect> Function(int logicalPage)? highlightFor,
    Color highlightColor = const Color(0x5580643B),
    void Function(int logicalPage, double nx, double ny)? onTap,
    VoidCallback? onBackgroundTap,
    ValueChanged<int>? onFocus,
    Widget Function(int, Widget)? wrapLeaf,
    List<Rect>? pageRegions,
    int? bookFirstPage,
    bool centerShortLandscapeSpread = false,
    bool fitToViewport = false,
    AudioVerticalFollower? verticalFollower,
  }) {
    final leftIndex = spreadIndex * 2;
    final rightIndex = leftIndex + 1;
    int pageAt(int physical) => bookFirstPage == null
        ? (physical == 0 ? rightIndex : leftIndex)
        : bookFirstPage + (1 - physical);

    Widget buildPage(int index, GlobalKey surfaceKey) {
      final path = imagePath(index);
      Widget image = QuranPageCache.getPage(path);

      if (isDarkMode) {
        image = ColorFiltered(colorFilter: invertFilter, child: image);
      }

      return _PageContent(
        surfaceKey: surfaceKey,
        image: image,
        aspectRatio: aspectRatio,
        highlightRects: highlightFor?.call(index) ?? const [],
        highlightColor: highlightColor,
        onTap: onTap == null && onFocus == null
            ? null
            : (nx, ny) {
                onFocus?.call(index);
                if (onTap != null) {
                  onTap(index, nx, ny);
                } else {
                  onBackgroundTap?.call();
                }
              },
      );
    }

    Widget framedPage(int index, AudioViewportHandle viewport) {
      final leaf = AspectRatio(
        key: ValueKey('quran-page-$index'),
        aspectRatio: aspectRatio,
        child: buildPage(index, viewport.pageKey(index)),
      );
      return wrapLeaf?.call(index, leaf) ?? leaf;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onBackgroundTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final clamped = pageScale.clamp(
            minPageScaleLandscape,
            maxPageScaleLandscape,
          );
          if (pageRegions != null) {
            // Book zoom is relative to a complete page fitted inside each
            // hinge-safe panel. Use the smaller fitted panel for BOTH pages so
            // navigation clearance or an off-centre hinge cannot change their
            // relative text size. Legacy/iPad spreads retain their width zoom.
            final bookWidth = bookFirstPage == null && !fitToViewport
                ? null
                : pageRegions
                          .map(
                            (region) => math.min(
                              region.width,
                              region.height * aspectRatio,
                            ),
                          )
                          .reduce(math.min) *
                      clamped;
            return Stack(
              children: [
                for (var physical = 0; physical < 2; physical++)
                  if (pageAt(physical) >= 1 && pageAt(physical) < totalPages)
                    Positioned.fromRect(
                      rect: pageRegions[physical],
                      child: AudioVerticalViewport(
                        pages: [pageAt(physical)],
                        follower: verticalFollower,
                        onScrollFocus: onFocus,
                        transformIdentity: (
                          clamped,
                          aspectRatio,
                          pageRegions[physical],
                          bookWidth,
                        ),
                        builder: (viewport) => bookWidth != null
                            ? Center(
                                child: SizedBox(
                                  width: bookWidth,
                                  child: framedPage(pageAt(physical), viewport),
                                ),
                              )
                            : SingleChildScrollView(
                                controller: viewport.scroll,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: SizedBox(
                                    width:
                                        pageRegions[physical].width * clamped,
                                    child: framedPage(
                                      pageAt(physical),
                                      viewport,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
              ],
            );
          }
          if (fitToViewport) {
            final width =
                math.min(
                  (constraints.maxWidth - 1) / 2,
                  constraints.maxHeight * aspectRatio,
                ) *
                clamped;
            return AudioVerticalViewport(
              pages: [
                if (rightIndex >= 1 && rightIndex < totalPages) rightIndex,
                if (leftIndex >= 1 && leftIndex < totalPages) leftIndex,
              ],
              follower: verticalFollower,
              onScrollFocus: onFocus,
              transformIdentity: (width, aspectRatio, constraints.biggest),
              builder: (viewport) => Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: width,
                      child: rightIndex >= 1 && rightIndex < totalPages
                          ? framedPage(rightIndex, viewport)
                          : null,
                    ),
                    const SizedBox(width: 1),
                    SizedBox(
                      width: width,
                      child: leftIndex >= 1 && leftIndex < totalPages
                          ? framedPage(leftIndex, viewport)
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }
          // Width-based zoom keeps both pages at their printed aspect ratio.
          final pageWidth = (constraints.maxWidth - 1) / 2 * clamped;

          return AudioVerticalViewport(
            pages: [
              if (rightIndex >= 1 && rightIndex < totalPages) rightIndex,
              if (leftIndex >= 1 && leftIndex < totalPages) leftIndex,
            ],
            follower: verticalFollower,
            onScrollFocus: onFocus,
            transformIdentity: (
              clamped,
              aspectRatio,
              constraints.biggest,
              centerShortLandscapeSpread,
            ),
            builder: (viewport) {
              Widget? leftPage;
              Widget? rightPage;

              if (rightIndex >= 1 && rightIndex < totalPages) {
                leftPage = SizedBox(
                  width: pageWidth,
                  child: framedPage(rightIndex, viewport),
                );
              }
              if (leftIndex >= 1 && leftIndex < totalPages) {
                rightPage = SizedBox(
                  width: pageWidth,
                  child: framedPage(leftIndex, viewport),
                );
              }

              final row = Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leftPage ?? SizedBox(width: pageWidth),
                  const SizedBox(width: 1),
                  rightPage ?? SizedBox(width: pageWidth),
                ],
              );

              // Only vertical scrolling belongs to the spread. A minimum
              // height centres short foldable pages without padding tall ones.
              return SingleChildScrollView(
                controller: viewport.scroll,
                scrollDirection: Axis.vertical,
                child: centerShortLandscapeSpread
                    ? ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(child: row),
                      )
                    : row,
              );
            },
          );
        },
      ),
    );
  }
}

class _PageContent extends StatelessWidget {
  final Key? surfaceKey;
  final Widget image;
  final double aspectRatio;
  final bool stretchToFit;
  final List<Rect> highlightRects;
  final Color highlightColor;
  final void Function(double nx, double ny)? onTap;

  const _PageContent({
    this.surfaceKey,
    required this.image,
    required this.aspectRatio,
    this.stretchToFit = false,
    required this.highlightRects,
    required this.highlightColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onTap == null
              ? null
              : (d) {
                  if (w <= 0 || h <= 0) return;
                  onTap!(
                    (d.localPosition.dx / w).clamp(0.0, 1.0),
                    (d.localPosition.dy / h).clamp(0.0, 1.0),
                  );
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: image),
              if (highlightRects.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _HighlightPainter(
                        highlightRects,
                        highlightColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (stretchToFit) {
      return SizedBox.expand(key: surfaceKey, child: surface);
    }
    return Center(
      child: AspectRatio(
        key: surfaceKey,
        aspectRatio: aspectRatio,
        child: surface,
      ),
    );
  }
}

/// Observes taps without adding a recognizer to Flutter's gesture arena.
/// This keeps two-finger scaling entirely owned by [InteractiveViewer].
class _BackgroundTapListener extends StatefulWidget {
  final VoidCallback? onBackgroundTap;
  final GlobalKey? pageSurfaceKey;
  final Widget Function(GlobalKey pageSurfaceKey) builder;

  const _BackgroundTapListener({
    required this.onBackgroundTap,
    required this.builder,
    this.pageSurfaceKey,
  });

  @override
  State<_BackgroundTapListener> createState() => _BackgroundTapListenerState();
}

class _BackgroundTapListenerState extends State<_BackgroundTapListener> {
  final GlobalKey _fallbackSurfaceKey = GlobalKey();
  GlobalKey get _pageSurfaceKey => widget.pageSurfaceKey ?? _fallbackSurfaceKey;
  int? _primaryPointer;
  Offset? _downPosition;
  bool _cancelTap = false;

  void _onPointerDown(PointerDownEvent event) {
    if (_primaryPointer != null) {
      // A second pointer means pinch/zoom, never a background tap.
      _cancelTap = true;
      return;
    }
    _primaryPointer = event.pointer;
    _downPosition = event.position;
    _cancelTap = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _primaryPointer || _downPosition == null) return;
    if ((event.position - _downPosition!).distance > 8) {
      _cancelTap = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _primaryPointer) return;
    if (!_cancelTap && !_pageContains(event.position)) {
      widget.onBackgroundTap?.call();
    }
    _resetPointer();
  }

  bool _pageContains(Offset globalPosition) {
    final renderObject = _pageSurfaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    final pageRect = MatrixUtils.transformRect(
      renderObject.getTransformTo(null),
      Offset.zero & renderObject.size,
    );
    return pageRect.contains(globalPosition);
  }

  void _resetPointer() {
    _primaryPointer = null;
    _downPosition = null;
    _cancelTap = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) => _resetPointer(),
      child: widget.builder(_pageSurfaceKey),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  final List<Rect> rects;
  final Color color;

  _HighlightPainter(this.rects, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final r in rects) {
      final scaled = Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(scaled, const Radius.circular(4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.rects != rects || old.color != color;
}
