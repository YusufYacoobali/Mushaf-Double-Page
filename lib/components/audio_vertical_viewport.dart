import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_motion.dart';
import '../utils/audio_vertical_follower.dart';

/// A page's real clipping viewport. A centred spread shares one scroll position;
/// separated regions use separate instances. Controllers live as long as the page.
class AudioVerticalViewport extends StatefulWidget {
  const AudioVerticalViewport({
    super.key,
    required this.pages,
    required this.builder,
    this.follower,
    this.onScrollFocus,
    this.transformed = false,
    this.transformationController,
    this.transformIdentity,
  });
  final List<int> pages;
  final Widget Function(AudioViewportHandle) builder;
  final AudioVerticalFollower? follower;
  final ValueChanged<int>? onScrollFocus;
  final bool transformed;
  final TransformationController? transformationController;
  final Object? transformIdentity;

  @override
  State<AudioVerticalViewport> createState() => _AudioVerticalViewportState();
}

class AudioViewportHandle {
  AudioViewportHandle._(this._state);
  final _AudioVerticalViewportState _state;
  ScrollController get scroll => _state._scroll;
  TransformationController get transform => _state._transform;
  GlobalKey pageKey(int page) => _state._keys[page]!;
  bool get verticalPanEnabled => _state._panEnabled;
  EdgeInsets get boundaryMargin => _state._boundaryMargin;
  EdgeInsets get scrollPadding => _state._scrollPadding;
}

class _PageSurface implements AudioVerticalSurface {
  _PageSurface(this.owner, this.page);
  final _AudioVerticalViewportState owner;
  final int page;
  @override
  AudioVerticalGeometry? measure(List<Rect> normalizedRects) =>
      owner._measure(page, normalizedRects);
  @override
  void moveBy(double delta, bool Function() valid) => owner._move(delta, valid);
  @override
  void cancel() => owner._animation.stop();
}

class _AudioVerticalViewportState extends State<AudioVerticalViewport>
    with SingleTickerProviderStateMixin {
  final _viewportKey = GlobalKey();
  final _keys = <int, GlobalKey>{};
  final _surfaces = <int, _PageSurface>{};
  final _scroll = ScrollController();
  late TransformationController _transform;
  late final AnimationController _animation;
  late final AudioViewportHandle _handle;
  bool _panEnabled = false, _metricsScheduled = false;
  EdgeInsets _boundaryMargin = EdgeInsets.zero;
  EdgeInsets _scrollPadding = EdgeInsets.zero;
  Rect? _readingViewport;
  (Size, EdgeInsets)? _screenGeometry;
  bool _paddingPending = false;
  int _clearanceGeneration = 0;
  void Function(double)? _apply;
  bool Function()? _valid;

  @override
  void initState() {
    super.initState();
    _handle = AudioViewportHandle._(this);
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_tick);
    _transform = widget.transformationController ?? TransformationController();
    _transform.addListener(_scheduleMetrics);
    _attach();
  }

  void _attach() {
    for (final page in widget.pages) {
      _keys.putIfAbsent(page, GlobalKey.new);
      final surface = _surfaces.putIfAbsent(
        page,
        () => _PageSurface(this, page),
      );
      widget.follower?.attach(page, surface);
    }
  }

  void _detach(AudioVerticalFollower? follower) {
    for (final entry in _surfaces.entries) {
      follower?.detach(entry.key, entry.value);
    }
  }

  @override
  void didUpdateWidget(AudioVerticalViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    final registrationChanged =
        !listEquals(oldWidget.pages, widget.pages) ||
        !identical(oldWidget.follower, widget.follower);
    final geometryChanged =
        registrationChanged ||
        oldWidget.transformIdentity != widget.transformIdentity ||
        oldWidget.transformed != widget.transformed ||
        !identical(
          oldWidget.transformationController,
          widget.transformationController,
        );
    if (geometryChanged) {
      _animation.stop();
      _resetClearance();
    }
    if (registrationChanged) _detach(oldWidget.follower);
    for (final page in _keys.keys.toList()) {
      if (!widget.pages.contains(page)) {
        _keys.remove(page);
        _surfaces.remove(page);
      }
    }
    if (!identical(
      oldWidget.transformationController,
      widget.transformationController,
    )) {
      _transform.removeListener(_scheduleMetrics);
      if (oldWidget.transformationController == null) _transform.dispose();
      _transform =
          widget.transformationController ?? TransformationController();
      _transform.addListener(_scheduleMetrics);
    } else if (oldWidget.transformIdentity != widget.transformIdentity &&
        widget.transformationController == null) {
      _transform.value = Matrix4.identity();
    }
    if (registrationChanged) _attach();
    if (geometryChanged) _scheduleMetrics();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animation.stop();
    final geometry = (
      MediaQuery.sizeOf(context),
      MediaQuery.paddingOf(context),
    );
    if (_screenGeometry != geometry) {
      _screenGeometry = geometry;
      _resetClearance();
    }
    _scheduleMetrics();
  }

  void _resetClearance() {
    _readingViewport = null;
    _scrollPadding = EdgeInsets.zero;
    _boundaryMargin = EdgeInsets.zero;
    _paddingPending = false;
    _clearanceGeneration++;
  }

  RenderBox? _box(GlobalKey key) {
    final object = key.currentContext?.findRenderObject();
    return object is RenderBox && object.attached && object.hasSize
        ? object
        : null;
  }

  Rect _globalRect(RenderBox box) => MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );

  Rect _visibleViewport(RenderBox box) {
    final media = MediaQuery.of(context);
    return _globalRect(box).intersect(
      Rect.fromLTRB(
        media.padding.left,
        media.padding.top,
        media.size.width - media.padding.right,
        media.size.height - media.padding.bottom,
      ),
    );
  }

  Rect _readingBand(
    Rect viewport,
    List<Rect> rects, {
    AudioVerticalGeometry Function(Rect)? measure,
    double? minimumLineHeight,
  }) {
    final reachable = rects.where((r) {
      final width =
          math.min(r.right, viewport.right) - math.max(r.left, viewport.left);
      return !r.isEmpty && width >= math.min(12, r.width * .25);
    });
    if (viewport.isEmpty || reachable.isEmpty) return viewport;
    final target = reachable.reduce((a, b) => a.expandToInclude(b));
    var bands = [viewport];
    for (final obstruction
        in widget.follower?.obstructions?.call() ?? <Rect>[]) {
      final blocked = obstruction.inflate(4);
      if (!viewport.overlaps(blocked) ||
          !reachable.any(
            (r) => r.right > blocked.left && r.left < blocked.right,
          )) {
        continue;
      }
      // Floating controls need not touch an edge. A vertical-only reveal uses
      // a clear band above or below controls that actually overlap the ayah.
      bands = [
        for (final band in bands)
          if (!band.overlaps(blocked))
            band
          else ...[
            if (blocked.top > band.top)
              Rect.fromLTRB(band.left, band.top, band.right, blocked.top),
            if (blocked.bottom < band.bottom)
              Rect.fromLTRB(band.left, blocked.bottom, band.right, band.bottom),
          ],
      ];
    }
    // A full-height side bar cannot be avoided by moving vertically. Do not
    // mistake the tiny gap beside its ends for a usable place to read a line.
    final firstLine = reachable.reduce((a, b) => a.top <= b.top ? a : b);
    bands.removeWhere(
      (band) => band.height + .5 < (minimumLineHeight ?? firstLine.height),
    );
    if (bands.isEmpty) return viewport;
    AudioVerticalGeometry geometry(Rect band) =>
        measure?.call(band) ??
        AudioVerticalGeometry(
          viewport: band,
          rects: rects,
          minDelta: -double.infinity,
          maxDelta: double.infinity,
        );
    int rank(Rect band) {
      final shift = Offset(0, -geometry(band).delta);
      bool contains(Rect rect) =>
          rect.top >= band.top - .5 && rect.bottom <= band.bottom + .5;
      if (contains(target.shift(shift))) return 0;
      return contains(firstLine.shift(shift)) ? 1 : 2;
    }

    bands.sort((a, b) {
      final reachability = rank(a).compareTo(rank(b));
      if (reachability != 0) return reachability;
      final fitsA = target.height <= a.height + .5;
      final fitsB = target.height <= b.height + .5;
      if (fitsA != fitsB) return fitsA ? -1 : 1;
      if (!fitsA && (a.height - b.height).abs() > .5) {
        return b.height.compareTo(a.height);
      }
      return geometry(a).delta.abs().compareTo(geometry(b).delta.abs());
    });
    if (measure != null && rank(bands.first) == 2) return viewport;
    return bands.first;
  }

  double _screenScale(RenderBox viewport) =>
      (viewport.localToGlobal(const Offset(0, 1)).dy -
              viewport.localToGlobal(Offset.zero).dy)
          .abs();

  AudioVerticalGeometry? _measure(int page, List<Rect> normalized) {
    if (_paddingPending) return null;
    final viewportBox = _box(_viewportKey), pageBox = _box(_keys[page]!);
    if (viewportBox == null || pageBox == null) return null;
    final transform = pageBox.getTransformTo(null);
    final rects = [
      for (final r in normalized)
        MatrixUtils.transformRect(
          transform,
          Rect.fromLTRB(
            r.left * pageBox.size.width,
            r.top * pageBox.size.height,
            r.right * pageBox.size.width,
            r.bottom * pageBox.size.height,
          ),
        ),
    ];
    final scale = _screenScale(viewportBox);
    if (scale <= 0) return null;
    final full = _globalRect(viewportBox), pageRect = _globalRect(pageBox);
    final scrollable =
        _scroll.hasClients && _scroll.position.hasContentDimensions;
    double clearance(Rect viewport) =>
        math.max(0.0, (full.bottom - viewport.bottom) / scale);
    AudioVerticalGeometry geometry(Rect viewport) {
      double minimum = 0, maximum = 0;
      if (widget.transformed) {
        // A fully fitted printed page needs neither movement nor recentering.
        if (pageRect.top < viewport.top - .5 ||
            pageRect.bottom > viewport.bottom + .5) {
          final ty = _transform.value.storage[13];
          final zoom = _transform.value.getMaxScaleOnAxis();
          final sceneHeight = viewportBox.size.height * zoom;
          final upper = math.max(
            _boundaryMargin.top * zoom,
            math.max(0, (viewport.top - full.top) / scale),
          );
          final lower =
              math.min(0, viewportBox.size.height - sceneHeight) -
              math.max(
                _boundaryMargin.bottom * zoom,
                math.max(0, (full.bottom - viewport.bottom) / scale),
              );
          minimum = (ty - upper) * scale;
          maximum = (ty - lower) * scale;
        }
      } else if (scrollable) {
        minimum = (_scroll.position.minScrollExtent - _scroll.offset) * scale;
        maximum =
            (_scroll.position.maxScrollExtent -
                _scroll.offset +
                math.max(0, clearance(viewport) - _scrollPadding.bottom)) *
            scale;
      }
      return AudioVerticalGeometry(
        viewport: viewport,
        rects: rects,
        minDelta: minimum,
        maxDelta: maximum,
      );
    }

    final viewport = _readingBand(
      _visibleViewport(viewportBox),
      rects,
      measure: geometry,
    );
    _readingViewport = viewport;
    _scheduleMetrics();
    if (!widget.transformed && scrollable) {
      final needed = clearance(viewport);
      if (needed > _scrollPadding.bottom + .5) {
        // Add room below the existing page without moving its initial pixels.
        // Keep it until the layout changes so a new verse cannot shrink the
        // scroll extent and snap a page that was already revealed.
        final generation = _clearanceGeneration;
        setState(() {
          _scrollPadding = EdgeInsets.only(bottom: needed);
          _paddingPending = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _clearanceGeneration) {
            _paddingPending = false;
          }
        });
        return null; // The follower retries after the new extent is laid out.
      }
    }
    return geometry(viewport);
  }

  void _move(double delta, bool Function() valid) {
    final viewport = _box(_viewportKey);
    if (viewport == null || !valid()) return;
    final scale = _screenScale(viewport);
    if (scale <= 0) return;
    _animation.stop();
    _valid = valid;
    if (widget.transformed) {
      final original = _transform.value.clone();
      final dy = delta / scale;
      _apply = (t) =>
          _transform.value = original.clone()
            ..setEntry(1, 3, original.storage[13] - dy * t);
    } else {
      if (!_scroll.hasClients) return;
      final start = _scroll.offset;
      final target = (start + delta / scale).clamp(
        _scroll.position.minScrollExtent,
        _scroll.position.maxScrollExtent,
      );
      _apply = (t) {
        if (_scroll.hasClients) _scroll.jumpTo(start + (target - start) * t);
      };
    }
    if (AppMotion.reduced(context)) {
      _apply!(1);
    } else {
      _animation.forward(from: 0);
    }
  }

  void _tick() {
    if (!mounted || !(_valid?.call() ?? false)) {
      _animation.stop();
      return;
    }
    _apply?.call(Curves.easeOutCubic.transform(_animation.value));
  }

  void _scheduleMetrics() {
    if (!mounted || !widget.transformed || _metricsScheduled) return;
    _metricsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _metricsScheduled = false;
      if (!mounted) return;
      final page = _box(_keys.values.first), viewport = _box(_viewportKey);
      if (page == null || viewport == null) return;
      final pageRect = _globalRect(page);
      final visible =
          _readingViewport ??
          _readingBand(_visibleViewport(viewport), [
            pageRect,
          ], minimumLineHeight: 16);
      final overflow =
          pageRect.top < visible.top - .5 ||
          pageRect.bottom > visible.bottom + .5;
      final full = _globalRect(viewport);
      final scale =
          _screenScale(viewport) * _transform.value.getMaxScaleOnAxis();
      final margin = scale <= 0
          ? EdgeInsets.zero
          : EdgeInsets.only(
              top: math.max(
                _boundaryMargin.top,
                math.max(0, visible.top - full.top) / scale,
              ),
              bottom: math.max(
                _boundaryMargin.bottom,
                math.max(0, full.bottom - visible.bottom) / scale,
              ),
            );
      if (overflow != _panEnabled || margin != _boundaryMargin) {
        setState(() {
          _panEnabled = overflow;
          _boundaryMargin = margin;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      widget.follower?.pointerDown(event.pointer);
      _scheduleMetrics();
    },
    onPointerUp: (event) => widget.follower?.pointerUp(event.pointer),
    onPointerCancel: (event) => widget.follower?.pointerUp(event.pointer),
    onPointerPanZoomStart: (event) =>
        widget.follower?.pointerDown(event.pointer),
    onPointerPanZoomEnd: (event) => widget.follower?.pointerUp(event.pointer),
    onPointerSignal: (_) => widget.follower?.manualActivity(),
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final follower = widget.follower;
        if (notification.depth != 0) return false;
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          follower?.userScroll(true);
          // A vertical drag has won the gesture arena. A provisional
          // horizontal swipe must leave focus and the saved page alone.
          if (widget.onScrollFocus != null) {
            final point = notification.dragDetails!.globalPosition;
            for (final entry in _keys.entries) {
              final box = _box(entry.value);
              if (box != null &&
                  (Offset.zero & box.size).contains(box.globalToLocal(point))) {
                widget.onScrollFocus!(entry.key);
                break;
              }
            }
          }
        } else if (notification is ScrollEndNotification &&
            (follower?.userScrolling ?? false)) {
          follower!.userScroll(false);
        }
        return false;
      },
      child: ClipRect(key: _viewportKey, child: widget.builder(_handle)),
    ),
  );

  @override
  void dispose() {
    _detach(widget.follower);
    _animation.dispose();
    _scroll.dispose();
    _transform.removeListener(_scheduleMetrics);
    if (widget.transformationController == null) _transform.dispose();
    super.dispose();
  }
}
