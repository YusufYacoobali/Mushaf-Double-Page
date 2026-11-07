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
    this.transformed = false,
    this.transformationController,
    this.transformIdentity,
  });
  final List<int> pages;
  final Widget Function(AudioViewportHandle) builder;
  final AudioVerticalFollower? follower;
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
    _scheduleMetrics();
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
    var viewport = _globalRect(box).intersect(
      Rect.fromLTRB(
        media.padding.left,
        media.padding.top,
        media.size.width - media.padding.right,
        media.size.height - media.padding.bottom,
      ),
    );
    for (final obstruction
        in widget.follower?.obstructions?.call() ?? <Rect>[]) {
      if (!viewport.overlaps(obstruction)) continue;
      if (obstruction.width >= viewport.width * .5 &&
          obstruction.bottom >= viewport.bottom - 3) {
        viewport = Rect.fromLTRB(
          viewport.left,
          viewport.top,
          viewport.right,
          math.max(viewport.top, obstruction.top - 4),
        );
      } else if (obstruction.height >= viewport.height * .5 &&
          obstruction.right >= viewport.right - 3) {
        viewport = Rect.fromLTRB(
          viewport.left,
          viewport.top,
          math.max(viewport.left, obstruction.left - 4),
          viewport.bottom,
        );
      }
    }
    return viewport;
  }

  double _screenScale(RenderBox viewport) =>
      (viewport.localToGlobal(const Offset(0, 1)).dy -
              viewport.localToGlobal(Offset.zero).dy)
          .abs();

  AudioVerticalGeometry? _measure(int page, List<Rect> normalized) {
    _scheduleMetrics();
    final viewportBox = _box(_viewportKey), pageBox = _box(_keys[page]!);
    if (viewportBox == null || pageBox == null) return null;
    final viewport = _visibleViewport(viewportBox);
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
    double minimum = 0, maximum = 0;
    if (widget.transformed) {
      final pageRect = _globalRect(pageBox);
      // If the whole printed surface fits, no movement or recentering is needed.
      if (pageRect.top < viewport.top - .5 ||
          pageRect.bottom > viewport.bottom + .5) {
        final ty = _transform.value.storage[13];
        final full = _globalRect(viewportBox);
        final sceneHeight =
            viewportBox.size.height * _transform.value.getMaxScaleOnAxis();
        final upper = math.max(0, (viewport.top - full.top) / scale);
        final lower =
            math.min(0, viewportBox.size.height - sceneHeight) -
            math.max(0, (full.bottom - viewport.bottom) / scale);
        minimum = (ty - upper) * scale;
        maximum = (ty - lower) * scale;
      }
    } else if (_scroll.hasClients && _scroll.position.hasContentDimensions) {
      minimum = (_scroll.position.minScrollExtent - _scroll.offset) * scale;
      maximum = (_scroll.position.maxScrollExtent - _scroll.offset) * scale;
    }
    return AudioVerticalGeometry(
      viewport: viewport,
      rects: rects,
      minDelta: minimum,
      maxDelta: maximum,
    );
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
      final pageRect = _globalRect(page), visible = _visibleViewport(viewport);
      final overflow =
          pageRect.top < visible.top - .5 ||
          pageRect.bottom > visible.bottom + .5;
      final full = _globalRect(viewport);
      final scale =
          _screenScale(viewport) * _transform.value.getMaxScaleOnAxis();
      final margin = scale <= 0
          ? EdgeInsets.zero
          : EdgeInsets.only(
              top: math.max(0, visible.top - full.top) / scale,
              bottom: math.max(0, full.bottom - visible.bottom) / scale,
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
    onPointerPanZoomStart: (event) => widget.follower?.pointerDown(event.pointer),
    onPointerPanZoomEnd: (event) => widget.follower?.pointerUp(event.pointer),
    onPointerSignal: (_) => widget.follower?.manualActivity(),
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final follower = widget.follower;
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
