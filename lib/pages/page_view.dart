import 'package:flutter/material.dart';
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
  static const double maxPageScalePortrait = 0.85;
  static const double minPageScaleLandscape = 0.60;
  static const double maxPageScaleLandscape = 0.9;

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
    Color highlightColor = const Color(0x553BA776),
    void Function(int logicalPage, double nx, double ny)? onTap,
    VoidCallback? onBackgroundTap,
    TransformationController? transformationController,
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
          // The old height-factor control stopped having a visible effect on
          // tall phones once the page was kept at its true aspect ratio: every
          // setting was capped by screen width. Scale the complete fitted page
          // instead, mapping the existing 70-85% preference range onto
          // 82-100% of the largest page that fits the viewport.
          final widthFromHeight = constraints.maxHeight * aspectRatio;
          final fittedWidth = widthFromHeight < constraints.maxWidth
              ? widthFromHeight
              : constraints.maxWidth;
          final fittedHeight = fittedWidth / aspectRatio;
          final visibleScale = clamped / maxPageScalePortrait;

          return InteractiveViewer(
            transformationController: transformationController,
            panEnabled: false,
            minScale: 1,
            maxScale: 3,
            child: Center(
              child: SizedBox(
                width: fittedWidth * visibleScale,
                height: fittedHeight * visibleScale,
                child: _PageContent(
                  surfaceKey: pageSurfaceKey,
                  image: image,
                  aspectRatio: aspectRatio,
                  highlightRects: highlightRects,
                  highlightColor: highlightColor,
                  onTap: onTap == null
                      ? null
                      : (nx, ny) => onTap(logicalPage, nx, ny),
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
    Color highlightColor = const Color(0x553BA776),
    void Function(int logicalPage, double nx, double ny)? onTap,
    VoidCallback? onBackgroundTap,
  }) {
    final leftIndex = spreadIndex * 2;
    final rightIndex = leftIndex + 1;

    Widget buildPage(int index) {
      final path = imagePath(index);
      Widget image = QuranPageCache.getPage(path);

      if (isDarkMode) {
        image = ColorFiltered(colorFilter: invertFilter, child: image);
      }

      return _PageContent(
        image: image,
        aspectRatio: aspectRatio,
        highlightRects: highlightFor?.call(index) ?? const [],
        highlightColor: highlightColor,
        onTap: onTap == null ? null : (nx, ny) => onTap(index, nx, ny),
      );
    }

    Widget framedPage(int index) {
      return AspectRatio(aspectRatio: aspectRatio, child: buildPage(index));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onBackgroundTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pageWidth = (constraints.maxWidth / 2 * pageScale).clamp(
            0.0,
            constraints.maxWidth / 2,
          );

          Widget? leftPage;
          Widget? rightPage;

          if (rightIndex < totalPages) {
            leftPage = SizedBox(
              width: pageWidth,
              child: framedPage(rightIndex),
            );
          }
          if (leftIndex < totalPages) {
            rightPage = SizedBox(
              width: pageWidth,
              child: framedPage(leftIndex),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leftPage != null) leftPage,
                if (leftPage != null && rightPage != null)
                  const SizedBox(width: 1),
                if (rightPage != null) rightPage,
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
  final List<Rect> highlightRects;
  final Color highlightColor;
  final void Function(double nx, double ny)? onTap;

  const _PageContent({
    this.surfaceKey,
    required this.image,
    required this.aspectRatio,
    required this.highlightRects,
    required this.highlightColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        key: surfaceKey,
        aspectRatio: aspectRatio,
        child: LayoutBuilder(
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
        ),
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
