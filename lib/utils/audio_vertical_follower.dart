import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'ayah_rect_index.dart';

/// Geometry is measured from the painted page into its clipped screen viewport,
/// after scrolling and InteractiveViewer transforms. Positive delta scrolls down.
class AudioVerticalGeometry {
  const AudioVerticalGeometry({
    required this.viewport,
    required this.rects,
    required this.minDelta,
    required this.maxDelta,
  });
  final Rect viewport;
  final List<Rect> rects;
  final double minDelta, maxDelta;

  ({Rect bounds, double margin, bool fits})? get _target {
    if (viewport.isEmpty) return null;
    Rect? bounds, firstLine;
    for (final rect in rects) {
      final horizontal = rect.intersect(
        Rect.fromLTRB(viewport.left, rect.top, viewport.right, rect.bottom),
      );
      if (horizontal.isEmpty ||
          horizontal.width < math.min(12, rect.width * .25)) {
        continue; // A vertical move cannot fix a wholly horizontal obstruction.
      }
      bounds = bounds?.expandToInclude(rect) ?? rect;
      if (firstLine == null || rect.top < firstLine.top) {
        firstLine = rect;
      }
    }
    if (bounds == null || firstLine == null) return null;
    final fits = bounds.height <= viewport.height + .5;
    // Relax the padding for an ayah that almost fills the viewport. If the
    // ayah is taller than the screen, its first line owns the reveal instead.
    final height = fits ? bounds.height : firstLine.height;
    final margin = math.min(
      16.0,
      math.max(0.0, (viewport.height - height) / 2),
    );
    return (bounds: bounds, margin: margin, fits: fits);
  }

  bool get visible {
    final target = _target;
    if (target == null) return false;
    if (!target.fits) {
      return (target.bounds.top - viewport.top - target.margin).abs() <= .5;
    }
    return target.bounds.top >= viewport.top + target.margin - .5 &&
        target.bounds.bottom <= viewport.bottom - target.margin + .5;
  }

  /// Keep every line of this page's ayah visible when it fits. Otherwise start
  /// with its first complete lines; following later lines needs audio timing.
  double get delta {
    if (visible || minDelta > maxDelta) return 0;
    final target = _target;
    if (target == null) return 0;
    final movement = target.fits
        ? target.bounds.center.dy - viewport.center.dy
        : target.bounds.top - viewport.top - target.margin;
    final clamped = movement.clamp(minDelta, maxDelta).toDouble();
    return clamped.abs() > .5 ? clamped : 0;
  }
}

abstract interface class AudioVerticalSurface {
  AudioVerticalGeometry? measure(List<Rect> normalizedRects);
  void moveBy(double delta, bool Function() valid);
  void cancel();
}

class AudioVerticalRequest {
  const AudioVerticalRequest._(
    this.revision,
    this.surah,
    this.ayah,
    this.mushaf,
  );
  final int revision, surah, ayah;
  final String mushaf;
}

typedef AudioAyahRects =
    List<Rect> Function(int page, int surah, int ayah, String mushaf);

/// Owns only vertical reveal requests. AudioPageFollower and ReaderPaging remain
/// the authorities for page navigation. No audio position subscription lives here.
class AudioVerticalFollower {
  AudioVerticalFollower({
    AudioAyahRects? rectsFor,
    this.obstructions,
    this.canFollow,
    this.interactionIdle = const Duration(milliseconds: 650),
  }) : _rectsFor =
           rectsFor ??
           ((page, surah, ayah, mushaf) =>
               AyahRectIndex.rectsFor(page, surah, ayah, mushaf: mushaf));

  final AudioAyahRects _rectsFor;
  final List<Rect> Function()? obstructions;
  final bool Function()? canFollow;
  final Duration interactionIdle;
  final _surfaces = <int, AudioVerticalSurface>{};
  final _pointers = <int>{};
  List<int> _visiblePages = const [];
  Object? _layout;
  bool Function()? _settled;
  String? _lastVerse;
  int _revision = 0, _layoutAttempts = 0;
  bool _scheduled = false, _disposed = false, _following = false;
  bool _scrolling = false, _coolingDown = false;
  Timer? _idle;
  AudioVerticalRequest? _pending;
  int? _pendingPage;
  bool Function()? _currentNavigation;

  bool get interacting => _pointers.isNotEmpty || _scrolling || _coolingDown;
  bool get userScrolling => _scrolling;

  void configureView({
    required Object layoutIdentity,
    required List<int> visiblePages,
    bool Function()? settled,
  }) {
    if (_disposed) return;
    if (_layout != layoutIdentity) {
      _layout = layoutIdentity;
      invalidate();
    } else if (!listEquals(_visiblePages, visiblePages)) {
      // Expected automatic page turns may change this set while awaiting goTo.
      // Manual navigation separately invalidates its request before changing it.
      for (final surface in _surfaces.values.toSet()) {
        surface.cancel();
      }
    }
    _visiblePages = List.of(visiblePages);
    _settled = settled;
    if (_settled?.call() ?? true) _schedule();
  }

  void attach(int page, AudioVerticalSurface surface) =>
      _surfaces[page] = surface;
  void detach(int page, AudioVerticalSurface surface) {
    if (identical(_surfaces[page], surface)) _surfaces.remove(page);
  }

  AudioVerticalRequest? beginAyah({
    required bool playing,
    required bool visible,
    required int session,
    required int? cycle,
    required int? surah,
    required int? ayah,
    required String mushaf,
  }) {
    if (_disposed) return null;
    if (!playing || surah == null || ayah == null) {
      if (_following) invalidate();
      _following = false;
      return null;
    }
    _following = true;
    final identity = '$session:$cycle:$surah:$ayah:$mushaf';
    if (!visible) {
      _lastVerse = identity;
      invalidate();
      return null;
    }
    if (identity == _lastVerse) return null;
    _lastVerse = identity;
    invalidate();
    return AudioVerticalRequest._(_revision, surah, ayah, mushaf);
  }

  bool _valid(AudioVerticalRequest request) =>
      !_disposed &&
      request.revision == _revision &&
      (_currentNavigation?.call() ?? true) &&
      (canFollow?.call() ?? true);

  void reveal(AudioVerticalRequest request, {int? preferredPage}) {
    if (!_valid(request)) return;
    _pending = request;
    _pendingPage = preferredPage;
    _layoutAttempts = 0;
    _schedule();
  }

  Future<void> revealAfterNavigation(
    AudioVerticalRequest request,
    Future<bool> navigation, {
    int? preferredPage,
    bool Function()? currentNavigation,
    VoidCallback? onSettled,
  }) async {
    if (await navigation && _valid(request)) {
      if (!(currentNavigation?.call() ?? true)) return;
      _currentNavigation = currentNavigation;
      onSettled?.call();
      reveal(request, preferredPage: preferredPage);
    }
  }

  void _schedule() {
    if (_disposed || _scheduled || _pending == null || interacting) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _dispatch();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _dispatch() {
    final request = _pending;
    if (request == null || interacting) return;
    if (!_valid(request)) {
      _pending = null;
      _pendingPage = null;
      return;
    }
    if (!(_settled?.call() ?? true)) return;
    final candidates = <(AudioVerticalSurface, AudioVerticalGeometry)>[];
    final pages = _pendingPage == null
        ? _visiblePages
        : _visiblePages.where((page) => page == _pendingPage);
    for (final page in pages) {
      final surface = _surfaces[page];
      final rects = _rectsFor(
        page,
        request.surah,
        request.ayah,
        request.mushaf,
      );
      if (surface == null || rects.isEmpty) continue;
      final geometry = surface.measure(rects);
      if (geometry != null) candidates.add((surface, geometry));
    }
    if (candidates.isEmpty && _layoutAttempts++ < 2) {
      _schedule();
      return;
    }
    _pending = null;
    _pendingPage = null;
    // The focused/target page owns a straddling ayah's reveal. Without an
    // explicit target, retain visible reading order rather than selecting the
    // smallest fragment on an unrelated leaf of the spread.
    if (candidates.isNotEmpty) {
      final (surface, geometry) = candidates.first;
      final movement = geometry.delta;
      if (movement.abs() > .5) {
        surface.moveBy(movement, () => _valid(request) && !interacting);
      }
    }
  }

  /// Invalidate pending layout/navigation work without forgetting which ayah was
  /// consumed. Position ticks must not pull a manually moved page back again.
  void invalidate() {
    _revision++;
    _pending = null;
    _pendingPage = null;
    _currentNavigation = null;
    for (final surface in _surfaces.values.toSet()) {
      surface.cancel();
    }
  }

  void pointerDown(int pointer) {
    _pointers.add(pointer);
    invalidate();
  }

  void pointerUp(int pointer) {
    _pointers.remove(pointer);
    _rest();
  }

  void userScroll(bool active) {
    if (active) invalidate();
    _scrolling = active;
    if (!active) _rest();
  }

  void manualActivity() {
    invalidate();
    _rest();
  }

  void _rest() {
    _coolingDown = true;
    _idle?.cancel();
    _idle = Timer(interactionIdle, () {
      _coolingDown = false;
      _schedule();
    });
  }

  void dispose() {
    invalidate();
    _disposed = true;
    _idle?.cancel();
    _surfaces.clear();
  }
}
