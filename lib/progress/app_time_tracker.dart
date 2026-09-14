import 'dart:async';
import 'package:flutter/widgets.dart';
import 'journey_store.dart';

/// One foreground clock above navigation, so routes and rebuilds never double
/// count app time. A monotonic clock excludes wall-clock/time-zone changes.
class AppTimeTracker with WidgetsBindingObserver {
  AppTimeTracker({
    Duration Function()? elapsed,
    Future<void> Function(int seconds)? saveSeconds,
  }) : _elapsedOverride = elapsed,
       _saveSeconds =
           saveSeconds ?? ((seconds) => JourneyStore.recordTime(app: seconds));
  static final instance = AppTimeTracker();
  final Duration Function()? _elapsedOverride;
  final Future<void> Function(int) _saveSeconds;
  final _clock = Stopwatch()..start();
  Timer? _timer;
  bool _started = false, _active = false;
  int _lastMs = 0, _remainderMs = 0;
  int get _nowMs => (_elapsedOverride?.call() ?? _clock.elapsed).inMilliseconds;

  void start() {
    if (_started) return;
    _started = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _active = state == null || state == AppLifecycleState.resumed;
    _lastMs = _nowMs;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(flush()),
    );
  }

  Future<void> flush() {
    if (!_started) return Future.value();
    final now = _nowMs;
    if (_active && now > _lastMs) _remainderMs += now - _lastMs;
    _lastMs = now;
    final seconds = _remainderMs ~/ 1000;
    _remainderMs %= 1000;
    return seconds > 0 ? _saveSeconds(seconds) : Future.value();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(flush());
    _active = state == AppLifecycleState.resumed;
  }

  void dispose() {
    unawaited(flush());
    _started = false;
    _active = false;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
