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

  bool get visible => rects.any((rect) => meaningfullyVisible(rect, viewport));

  static bool meaningfullyVisible(Rect rect, Rect viewport) {
    if (rect.isEmpty || viewport.isEmpty) return false;
    final inside = rect.intersect(viewport.deflate(3));
    return !inside.isEmpty &&
        inside.width >= math.min(12, rect.width * .25) &&
        inside.height >= math.min(12, rect.height * .4);
  }

  /// Reveal one nearby line, rather than centring the ayah's bounding box or
  /// chasing every off-screen line of a multi-line / straddling ayah.
  double get delta {
    if (visible || viewport.isEmpty || minDelta > maxDelta) return 0;
    double? nearest;
    for (final rect in rects) {
      final horizontal = rect.intersect(
        Rect.fromLTRB(viewport.left, rect.top, viewport.right, rect.bottom),
      );
      if (horizontal.isEmpty ||
          horizontal.width < math.min(12, rect.width * .25)) {
        continue; // A vertical move cannot fix a wholly horizontal obstruction.
      }
      const margin = 16.0;
      final revealHeight = math.min(
        rect.height,
        math.max(1, viewport.height - 2 * margin),
      );
      final movement = rect.center.dy >= viewport.center.dy
          ? rect.top + revealHeight - viewport.bottom + margin
          : rect.bottom - revealHeight - viewport.top - margin;
      final clamped = movement.clamp(minDelta, maxDelta).toDouble();
      if (clamped.abs() > .5 &&
          (nearest == null || clamped.abs() < nearest.abs())) {
        nearest = clamped;
      }
    }
    return nearest ?? 0;
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

  void reveal(AudioVerticalRequest request) {
    if (!_valid(request)) return;
    _pending = request;
    _layoutAttempts = 0;
    _schedule();
  }

  Future<void> revealAfterNavigation(
    AudioVerticalRequest request,
    Future<bool> navigation, {
    bool Function()? currentNavigation,
    VoidCallback? onSettled,
  }) async {
    if (await navigation && _valid(request)) {
      if (!(currentNavigation?.call() ?? true)) return;
      _currentNavigation = currentNavigation;
      onSettled?.call();
      reveal(request);
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
      return;
    }
    if (!(_settled?.call() ?? true)) return;
    final candidates = <(AudioVerticalSurface, AudioVerticalGeometry)>[];
    for (final page in _visiblePages) {
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
    if (candidates.any((c) => c.$2.visible)) return;
    candidates.removeWhere((c) => c.$2.delta.abs() <= .5);
    candidates.sort((a, b) => a.$2.delta.abs().compareTo(b.$2.delta.abs()));
    if (candidates.isNotEmpty) {
      final (surface, geometry) = candidates.first;
      surface.moveBy(geometry.delta, () => _valid(request) && !interacting);
    }
  }

  /// Invalidate pending layout/navigation work without forgetting which ayah was
  /// consumed. Position ticks must not pull a manually moved page back again.
  void invalidate() {
    _revision++;
    _pending = null;
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
