import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'journey_store.dart';

/// Counts page visits without treating rebuilds or rotation as new visits.
class PageVisitTracker {
  Set<String> _visible = {};
  int show(Iterable<String> pages) {
    final next = pages.toSet();
    final added = next.difference(_visible).length;
    _visible = next;
    return added;
  }
}

class ReaderActivity extends StatefulWidget {
  const ReaderActivity({super.key, required this.pages, required this.child});
  final List<String> pages;
  final Widget child;
  @override
  State<ReaderActivity> createState() => _ReaderActivityState();
}

class _ReaderActivityState extends State<ReaderActivity>
    with WidgetsBindingObserver {
  final _pages = PageVisitTracker();
  Timer? _timer;
  int _seconds = 0;
  bool get _active =>
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      (ModalRoute.of(context)?.isCurrent ?? true);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_active) {
        _flush();
        return;
      }
      _recordPages();
      if (++_seconds >= 15) _flush();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recordPages();
    });
  }

  void _recordPages() {
    if (!_active) return;
    unawaited(JourneyStore.recordPages(_pages.show(widget.pages)));
  }

  void _flush() {
    final seconds = _seconds;
    _seconds = 0;
    unawaited(JourneyStore.recordTime(reading: seconds));
  }

  @override
  void didUpdateWidget(ReaderActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recordPages();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _flush();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flush();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A translation must actually be on screen for two seconds. Lazy-list cache,
/// collapsed text and covered/background routes do not count as reading.
class TranslationExposure extends StatefulWidget {
  const TranslationExposure({
    super.key,
    required this.verse,
    required this.seen,
    required this.child,
  });
  final String verse;
  final Set<String> seen;
  final Widget child;
  @override
  State<TranslationExposure> createState() => _TranslationExposureState();
}

class _TranslationExposureState extends State<TranslationExposure> {
  Timer? _timer;
  int _visibleTicks = 0;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  void _check() {
    if (widget.seen.contains(widget.verse)) return;
    final state = WidgetsBinding.instance.lifecycleState;
    final box = context.findRenderObject();
    if ((state != null && state != AppLifecycleState.resumed) ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
        box is! RenderBox ||
        !box.hasSize) {
      _visibleTicks = 0;
      return;
    }
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    var screen = Offset.zero & MediaQuery.sizeOf(context);
    final Object? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is RenderBox && viewport.hasSize) {
      screen = screen.intersect(
        viewport.localToGlobal(Offset.zero) & viewport.size,
      );
    }
    final visible = bounds.intersect(screen);
    if (visible.width <= 0 || visible.height < 24) {
      _visibleTicks = 0;
      return;
    }
    if (++_visibleTicks >= 2 && widget.seen.add(widget.verse)) {
      unawaited(JourneyStore.recordTranslation());
    }
  }

  @override
  void didUpdateWidget(TranslationExposure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verse != widget.verse) _visibleTicks = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Measures advancing playback, rejecting jumps/seeks and paused time. A listen
/// counts once after 90% of the ayah's duration has actually played.
class ListeningTracker {
  ListeningTracker({required this.onListen, required this.onSeconds});
  final void Function(String verse) onListen;
  final void Function(int seconds) onSeconds;
  String? _occurrence;
  int _lastMs = 0, _heardMs = 0, _pendingMs = 0;
  bool _counted = false, _wasPlaying = false;
  void sample({
    required String occurrence,
    required String verse,
    required Duration position,
    required Duration? duration,
    required bool playing,
    bool countVerse = true,
  }) {
    final ms = position.inMilliseconds;
    if (_occurrence != occurrence) {
      _occurrence = occurrence;
      _heardMs = 0;
      _counted = false;
      _wasPlaying = false;
    } else if (ms < _lastMs - 250) {
      // Retry/seek within one occurrence cannot count the same listen twice.
      _heardMs = 0;
      _wasPlaying = false;
    }
    final delta = ms - _lastMs;
    if (_wasPlaying && delta > 0 && delta <= 1500) {
      _heardMs += delta;
      _pendingMs += delta;
      if (_pendingMs >= 15000) flush();
    }
    _lastMs = ms;
    _wasPlaying = playing;
    if (countVerse &&
        !_counted &&
        duration != null &&
        duration.inMilliseconds > 0 &&
        _heardMs >= duration.inMilliseconds * .9) {
      _counted = true;
      onListen(verse);
    }
    if (!playing) flush();
  }

  void flush() {
    final seconds = _pendingMs ~/ 1000;
    _pendingMs %= 1000;
    if (seconds > 0) onSeconds(seconds);
  }

  void reset() {
    flush();
    _occurrence = null;
    _wasPlaying = false;
  }
}
