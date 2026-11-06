import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/cache.dart';

class QuranPageView {
  // Each geometry index is generated in its printed image's native coordinate
  // space. Keep the visible page at that same aspect ratio so taps and
  // highlights stay aligned.
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
    ValueChanged<int>? onFocus,
  }) {
    final clamped = pageScale.clamp(minPageScalePortrait, maxPageScalePortrait);
    final path = imagePath(logicalPage);
    Widget image = QuranPageCache.getPage(path);

    if (isDarkMode) {
      image = ColorFiltered(colorFilter: invertFilter, child: image);
    }

    return _BackgroundTapListener(
      onBackgroundTap: onBackgroundTap,
      builder: (pageSurfaceKey) => LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(
            constraints.maxWidth,
            constraints.maxHeight * clamped * aspectRatio,
          );
          return SizedBox.expand(
            child: InteractiveViewer(
              key: ValueKey(clamped),
              transformationController: transformationController,
              constrained: false,
              panEnabled: false,
              minScale: 1,
              maxScale: maxPageScalePortrait / clamped,
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Center(
                  child: SizedBox(
                    key: ValueKey('quran-page-$logicalPage'),
                    width: width,
                    height: width / aspectRatio,
                    child: Listener(
                      onPointerDown: (_) => onFocus?.call(logicalPage),
                      child: _PageContent(
                        surfaceKey: pageSurfaceKey,
                        image: image,
                        aspectRatio: aspectRatio,
                        stretchToFit: true,
                        highlightRects: highlightRects,
                        highlightColor: highlightColor,
                        onTap: onTap == null
                            ? null
                            : (nx, ny) => onTap(logicalPage, nx, ny),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
    List<Rect>? pageRegions,
  }) {
    final leftIndex = spreadIndex * 2;
    final rightIndex = leftIndex + 1;

    Widget buildPage(int index) {
      final path = imagePath(index);
      Widget image = QuranPageCache.getPage(path);

      if (isDarkMode) {
        image = ColorFiltered(colorFilter: invertFilter, child: image);
      }

      return Listener(
        onPointerDown: (_) => onFocus?.call(index),
        child: _PageContent(
          image: image,
          aspectRatio: aspectRatio,
          highlightRects: highlightFor?.call(index) ?? const [],
          highlightColor: highlightColor,
          onTap: onTap == null ? null : (nx, ny) => onTap(index, nx, ny),
        ),
      );
    }

    Widget framedPage(int index) {
      return AspectRatio(
        key: ValueKey('quran-page-$index'),
        aspectRatio: aspectRatio,
        child: buildPage(index),
      );
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
            return Stack(
              children: [
                for (var physical = 0; physical < 2; physical++)
                  if ((physical == 0 ? rightIndex : leftIndex) >= 1 &&
                      (physical == 0 ? rightIndex : leftIndex) < totalPages)
                    Positioned.fromRect(
                      rect: pageRegions[physical],
                      child: ClipRect(
                        child: SingleChildScrollView(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: pageRegions[physical].width * clamped,
                              child: framedPage(
                                physical == 0 ? rightIndex : leftIndex,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          }
          // Landscape toolbar zoom changes only the spread width. At minimum
          // both full pages fit vertically; at maximum they nearly fill the
          // screen width. The spread always starts at the top and is centred.
          final pageWidth = (constraints.maxWidth - 1) / 2 * clamped;

          Widget? leftPage;
          Widget? rightPage;

          if (rightIndex >= 1 && rightIndex < totalPages) {
            leftPage = SizedBox(
              width: pageWidth,
              child: framedPage(rightIndex),
            );
          }
          if (leftIndex >= 1 && leftIndex < totalPages) {
            rightPage = SizedBox(
              width: pageWidth,
              child: framedPage(leftIndex),
            );
          }

          // Only vertical scrolling belongs to the spread. Horizontal gestures
          // must reach the enclosing PageView to turn the page.
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leftPage ?? SizedBox(width: pageWidth),
                const SizedBox(width: 1),
                rightPage ?? SizedBox(width: pageWidth),
              ],
            ),
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
  final Widget Function(GlobalKey pageSurfaceKey) builder;

  const _BackgroundTapListener({
    required this.onBackgroundTap,
    required this.builder,
  });

  @override
  State<_BackgroundTapListener> createState() => _BackgroundTapListenerState();
}

class _BackgroundTapListenerState extends State<_BackgroundTapListener> {
  final GlobalKey _pageSurfaceKey = GlobalKey();
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
    final pageRect =
        renderObject.localToGlobal(Offset.zero) & renderObject.size;
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
