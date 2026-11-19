import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../utils/app_motion.dart';
import '../utils/reader_layout.dart';
import '../utils/reader_paging.dart';
import 'quran_page_turn_painter.dart';

typedef WrapPageLeaf = Widget Function(int page, Widget child);
typedef BuildTurnSurface =
    Widget Function(int index, bool active, WrapPageLeaf wrapLeaf);

/// Owns the live reader and a bounded window of paintable adjacent surfaces.
/// Only the active surface receives gestures, focus and audio registrations.
class QuranPageTurnView extends StatefulWidget {
  const QuranPageTurnView({
    super.key,
    required this.paging,
    required this.layout,
    required this.layoutIdentity,
    required this.buildSurface,
    required this.isDarkMode,
    required this.onPageChanged,
    this.onUserTurn,
  });

  final ReaderPaging paging;
  final ReaderLayout layout;
  final Object layoutIdentity;
  final BuildTurnSurface buildSurface;
  final bool isDarkMode;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<bool>? onUserTurn;

  /// In single-page mode InteractiveViewer owns the scale/pan recognizer.
  /// It forwards its win in the gesture arena, retaining both fingers if a
  /// horizontal drag subsequently becomes a pinch.
  static void singlePageGesture(
    BuildContext context,
    TransformationController transform,
  ) {
    context.findAncestorStateOfType<_QuranPageTurnViewState>()?._singleGesture(
      transform,
    );
  }

  static bool allowVerticalPan(BuildContext context) =>
      context
          .findAncestorStateOfType<_QuranPageTurnViewState>()
          ?._manualActivity !=
      true;

  @override
  State<QuranPageTurnView> createState() => _QuranPageTurnViewState();
}

class _QuranPageTurnViewState extends State<QuranPageTurnView>
    with SingleTickerProviderStateMixin {
  ReaderPaging get _paging => widget.paging;
  final _host = GlobalKey();
  final _live = _LeafBoundaries();
  final _neighbors = <int, _LeafBoundaries>{};
  late final AnimationController _animation;
  late int _generation, _operation;
  late PageTurnPhase _phase;
  bool _reduced = false;
  bool _manualActivity = false;

  List<PageTurnLeaf>? _source, _destination;
  int? _captureOperation, _animationOperation, _capturedIndex;
  Duration? _captureStart;
  bool _captureFailed = false;

  final _pointers = <int>{};
  int? _candidate, _dragOperation;
  Offset _origin = Offset.zero, _travel = Offset.zero;
  VelocityTracker? _velocity;
  Matrix4? _initialTransform;
  bool _accepted = false;
  double _leafWidth = 1;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this)..addListener(_tick);
    _attach();
  }

  void _attach() {
    _paging.attach(this);
    _generation = _paging.generation;
    _operation = _paging.operation;
    _phase = _paging.phase;
    _paging.addListener(_onNavigation);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AppMotion.reduced(context);
    if (reduced && !_reduced && _paging.phase == PageTurnPhase.settling) {
      final token = _paging.operation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _reduced) _finish(token);
      });
    }
    _reduced = reduced;
  }

  @override
  void didUpdateWidget(QuranPageTurnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.paging, _paging)) {
      oldWidget.paging.removeListener(_onNavigation);
      oldWidget.paging.detach(this);
      _resetTurn();
      _attach();
    } else if (_generation != _paging.generation ||
        oldWidget.layoutIdentity != widget.layoutIdentity) {
      if (_generation == _paging.generation) _paging.geometryChanged();
      _generation = _paging.generation;
      _operation = _paging.operation;
      _phase = _paging.phase;
      _resetTurn();
    }
  }

  void _resetTurn() {
    _animationOperation = null;
    _animation.stop();
    _captureOperation = null;
    _captureStart = null;
    _captureFailed = false;
    _capturedIndex = null;
    _dragOperation = null;
    _candidate = null;
    _setManualActivity(false);
    final leaves = [...?_source, ...?_destination];
    _source = null;
    _destination = null;
    if (leaves.isNotEmpty) {
      // A painter from the preceding frame may still be in the render tree.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _disposeLeaves(leaves),
      );
    }
  }

  static void _disposeLeaves(List<PageTurnLeaf> leaves) {
    for (final leaf in leaves) {
      leaf.image?.dispose();
    }
  }

  void _setManualActivity(bool active) {
    if (_manualActivity == active) return;
    _manualActivity = active;
    widget.onUserTurn?.call(active);
  }

  void _onNavigation() {
    // Progress changes repaint the frozen mesh without rebuilding page widgets.
    final op = _paging.operation;
    final phase = _paging.phase;
    if (_operation == op && _phase == phase) return;
    final startingDrag = phase == PageTurnPhase.dragging;
    // A new audio target can be the other page of the same incoming spread.
    // Preserve the bend and textures, and give its animation the new token.
    final sameIncomingSpread =
        phase == PageTurnPhase.settling &&
        _phase == PageTurnPhase.settling &&
        _paging.progress > 0 &&
        _destination != null &&
        _capturedIndex == _paging.destinationIndex;
    if (sameIncomingSpread) {
      _animationOperation = null;
      _animation.stop();
    } else if (_operation != op || phase == PageTurnPhase.idle) {
      // startDrag notifies synchronously, before its caller receives the token.
      final candidate = _candidate;
      _resetTurn();
      if (startingDrag) _candidate = candidate;
    }
    _operation = op;
    _phase = phase;
    if (startingDrag) _setManualActivity(true);
    _rebuild();
    if (phase != PageTurnPhase.idle && !_reduced) _scheduleCapture();
    if (phase == PageTurnPhase.settling) _startSettlement();
  }

  void _rebuild() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _scheduleCapture() {
    final token = _paging.operation;
    if (_captureOperation == token || _captureFailed || _destination != null) {
      return;
    }
    _captureOperation = token;
    WidgetsBinding.instance.addPostFrameCallback((now) {
      if (!mounted ||
          _paging.operation != token ||
          _captureOperation != token) {
        return;
      }
      _captureOperation = null;
      if (_paging.phase == PageTurnPhase.idle || _reduced) return;
      _captureStart ??= now;
      final host = _host.currentContext?.findRenderObject();
      final next = _paging.destinationIndex!;
      try {
        if (host is RenderBox) {
          _source ??= _capture(_live, _paging.index, host);
          final neighbor = _neighbors[next];
          if (_source != null && neighbor != null) {
            _destination = _capture(neighbor, next, host);
            if (_destination != null) _capturedIndex = next;
          }
        }
      } on Object {
        // A detached layer, invalidated image or unsupported raster backend
        // must still allow the requested turn to settle.
        _captureFailed = true;
      }
      if (_destination == null &&
          now - _captureStart! >= const Duration(milliseconds: 350)) {
        _captureFailed = true;
      }
      if (_destination == null && !_captureFailed) {
        _scheduleCapture();
      } else {
        setState(() {});
        _startSettlement();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  List<PageTurnLeaf>? _capture(
    _LeafBoundaries leaves,
    int index,
    RenderBox host,
  ) {
    final pages = [
      _paging.pageAt(index, left: true),
      if (!_paging.singlePage) _paging.pageAt(index, left: false),
    ];
    final boxes = <RenderRepaintBoundary?>[];
    for (final page in pages) {
      if (page == null) {
        boxes.add(null);
      } else {
        final box = leaves.keys[page]?.currentContext?.findRenderObject();
        if (box is! RenderRepaintBoundary ||
            !box.attached ||
            !box.hasSize ||
            box.size.isEmpty ||
            !_hasDecodedImages(box)) {
          return null;
        }
        boxes.add(box);
      }
    }

    final bounds = [
      for (final box in boxes)
        if (box == null)
          Rect.zero
        else
          MatrixUtils.transformRect(
            box.getTransformTo(host),
            Offset.zero & box.size,
          ),
    ];
    if (boxes.contains(null) && boxes.length == 2) {
      final blank = boxes.indexOf(null);
      final other = bounds[1 - blank];
      final regions = widget.layout.pageRegions;
      // Continuous spreads retain their actual page width and one-pixel gap.
      // On split screens the empty slot belongs to its own physical panel.
      final offset =
          widget.layout.spreadLayout == ReaderSpreadLayout.centeredLandscape
          ? Offset((blank == 0 ? -1 : 1) * (other.width + 1), 0)
          : regions[blank].center - regions[1 - blank].center;
      bounds[blank] = other.shift(offset);
    }

    final result = <PageTurnLeaf>[];
    try {
      for (var i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        ui.Image? image;
        if (box != null) {
          final logical = box.size;
          // At most four textures. Cap each at 1.25 MP and 2048 px per side
          // even when the source is deeply zoomed or taller than its viewport.
          final ratio = [
            MediaQuery.devicePixelRatioOf(context) *
                bounds[i].width /
                logical.width,
            2048 / logical.longestSide,
            math.sqrt(1250000 / (logical.width * logical.height)),
          ].reduce(math.min);
          if (!ratio.isFinite || ratio <= 0) {
            throw StateError('Invalid page bounds');
          }
          image = box.toImageSync(pixelRatio: ratio);
        }
        result.add(PageTurnLeaf(bounds: bounds[i], image: image));
      }
      return result;
    } on Object {
      _disposeLeaves(result);
      rethrow;
    }
  }

  static bool _hasDecodedImages(RenderObject root) {
    if (root is RenderImage) return root.image != null;
    var ready = true;
    root.visitChildren((child) {
      if (ready) ready = _hasDecodedImages(child);
    });
    return ready;
  }

  void _tick() {
    final token = _animationOperation;
    if (token != null) _paging.setProgress(token, _animation.value);
  }

  void _startSettlement() {
    if (_paging.phase != PageTurnPhase.settling) return;
    final token = _paging.operation;
    if (_animationOperation == token) return;
    final end = _paging.completing ? 1.0 : 0.0;
    if (_reduced || _captureFailed || _paging.progress == end) {
      _finish(token);
      return;
    }
    if (_destination == null) return;
    _animationOperation = token;
    _animation.value = _paging.progress;
    final millis = (350 * (end - _paging.progress).abs()).round().clamp(1, 350);
    _animation
        .animateTo(
          end,
          duration: Duration(milliseconds: millis),
          curve: Curves.easeOut,
        )
        .whenCompleteOrCancel(() {
          if (mounted && _animationOperation == token) _finish(token);
        });
  }

  void _finish(int token) {
    if (_paging.completeTurn(token) && token == _paging.operation) {
      widget.onPageChanged(_paging.focusedPage);
    }
  }

  void _down(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (_pointers.length != 1) {
      _candidate = null;
      if (_paging.phase == PageTurnPhase.dragging) _paging.cancelTurn();
      return;
    }
    if (!_paging.settled ||
        e.buttons != kPrimaryButton ||
        !_clipRegions.any((region) => region.contains(e.localPosition))) {
      return;
    }
    _candidate = e.pointer;
    _initialTransform = null;
    _origin = e.localPosition;
    _travel = Offset.zero;
    _accepted = false;
    _velocity = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
  }

  void _move(PointerMoveEvent e) {
    if (_candidate != e.pointer) return;
    _velocity?.addPosition(e.timeStamp, e.position);
    _travel = e.localPosition - _origin;
    if (_dragOperation == null &&
        _travel.dy.abs() > kTouchSlop &&
        _travel.dy.abs() > _travel.dx.abs()) {
      _candidate = null;
      return;
    }
    if (_accepted) _updateDrag();
  }

  void _singleGesture(TransformationController transform) {
    if (_candidate == null) return;
    _initialTransform ??= transform.value.clone();
    _acceptDrag();
    // InteractiveViewer applies its pan before forwarding this callback.
    // Pin the vertical position on the very first, possibly diagonal update,
    // before the rebuilt viewer can disable panning for this horizontal turn.
    if (_dragOperation != null && transform.value != _initialTransform) {
      transform.value = _initialTransform!;
    }
  }

  void _acceptDrag() {
    if (_candidate == null) return;
    _accepted = true;
    _updateDrag();
  }

  void _updateDrag() {
    if (_dragOperation == null) {
      if (_travel.dx.abs() <= kTouchSlop ||
          _travel.dx.abs() <= _travel.dy.abs()) {
        return;
      }
      final direction = _travel.dx.sign.toInt();
      _leafWidth = _turnWidth(direction);
      if (!_paging.startDrag(direction)) return;
      _dragOperation = _paging.operation;
    }
    if (_dragOperation != _paging.operation) return;
    final direction = _paging.destinationIndex! - _paging.index;
    _paging.dragTo(_travel.dx * direction / _leafWidth);
  }

  double _turnWidth(int direction) {
    final page = _paging.pageAt(_paging.index, left: direction > 0);
    final host = _host.currentContext?.findRenderObject();
    final box = _live.keys[page]?.currentContext?.findRenderObject();
    final available = widget.layout.usableContentBounds.width;
    if (box is RenderBox && box.hasSize && host is RenderBox) {
      final width = MatrixUtils.transformRect(
        box.getTransformTo(host),
        Offset.zero & box.size,
      ).width;
      if (width > 0) return math.min(available, width);
    }
    return widget.layout.singlePage
        ? available
        : widget.layout.pageRegions[direction > 0 ? 0 : 1].width;
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_candidate != event.pointer) return;
    _candidate = null;
    if (_dragOperation != _paging.operation) return;
    _dragOperation = null;
    if (event is PointerCancelEvent) {
      _paging.settleDrag(commit: false);
      return;
    }
    final direction = _paging.destinationIndex! - _paging.index;
    final speed =
        (_velocity?.getVelocity().pixelsPerSecond.dx ?? 0) * direction;
    _paging.settleDrag(
      commit: speed >= 500 || (speed > -500 && _paging.progress >= .35),
    );
  }

  void _semanticTurn(int direction) {
    if (_paging.startDrag(direction)) _paging.settleDrag(commit: true);
  }

  List<Rect> get _clipRegions =>
      widget.layout.spreadLayout == ReaderSpreadLayout.separateRegions &&
          !_paging.singlePage
      ? widget.layout.pageRegions
      : [widget.layout.usableContentBounds];

  @override
  Widget build(BuildContext context) {
    final index = _paging.index;
    final previews = <int>[
      if (!_reduced && index > 0) index - 1,
      if (!_reduced && index + 1 < _paging.pageCount) index + 1,
    ];
    _live.retainPages(_paging, index);
    _neighbors.removeWhere((i, _) => !previews.contains(i));
    final source = _source, destination = _destination;
    final paint =
        !_reduced &&
        source != null &&
        destination != null &&
        _paging.destinationIndex != null;
    final stack = Stack(
      key: _host,
      fit: StackFit.expand,
      children: [
        for (final neighbor in previews)
          _PaintedOffstage(
            key: ValueKey(('prepare', neighbor)),
            child: ExcludeFocus(
              child: widget.buildSurface(
                neighbor,
                false,
                (_neighbors[neighbor] ??= _LeafBoundaries()).wrap,
              ),
            ),
          ),
        AbsorbPointer(
          absorbing: _paging.phase == PageTurnPhase.settling,
          child: Opacity(
            opacity: paint ? 0 : 1,
            child: KeyedSubtree(
              key: ValueKey(index),
              child: widget.buildSurface(index, true, _live.wrap),
            ),
          ),
        ),
        if (paint)
          IgnorePointer(
            child: ListenableBuilder(
              listenable: _paging,
              builder: (context, _) => CustomPaint(
                painter: QuranPageTurnPainter(
                  source: source,
                  destination: destination,
                  forward: (_paging.destinationIndex ?? index) > index,
                  progress: _paging.progress,
                  clipRegions: _clipRegions,
                  paperColor: widget.isDarkMode
                      ? const Color(0xff191919)
                      : const Color(0xfffaf8f0),
                ),
              ),
            ),
          ),
      ],
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      onScrollRight: _paging.settled && index + 1 < _paging.pageCount
          ? () => _semanticTurn(1)
          : null,
      onScrollLeft: _paging.settled && index > 0
          ? () => _semanticTurn(-1)
          : null,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onHorizontalDragStart: _paging.singlePage
              ? null
              : (_) => _acceptDrag(),
          child: stack,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _paging.removeListener(_onNavigation);
    _paging.detach(this);
    _animationOperation = null;
    _animation.dispose();
    _setManualActivity(false);
    _disposeLeaves([...?_source, ...?_destination]);
    super.dispose();
  }
}

class _LeafBoundaries {
  final keys = <int, GlobalKey>{};

  void retainPages(ReaderPaging paging, int index) {
    keys.removeWhere(
      (page, _) =>
          page != paging.pageAt(index, left: false) &&
          page != paging.pageAt(index, left: true),
    );
  }

  Widget wrap(int page, Widget child) =>
      RepaintBoundary(key: keys.putIfAbsent(page, GlobalKey.new), child: child);
}

/// Offstage's semantics, focus, hit-test and onstage-element isolation, with a
/// retained paint layer so the page-only repaint boundaries can be captured.
class _PaintedOffstage extends Offstage {
  const _PaintedOffstage({super.key, required super.child});

  @override
  RenderOffstage createRenderObject(BuildContext context) =>
      _RenderPaintedOffstage();
}

class _RenderPaintedOffstage extends RenderOffstage {
  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    layer = context.pushOpacity(offset, 0, (context, offset) {
      context.paintChild(child!, offset);
    }, oldLayer: layer as OpacityLayer?);
  }
}
