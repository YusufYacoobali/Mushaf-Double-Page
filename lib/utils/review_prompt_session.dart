import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One instance lasts for the app process, including background/resume cycles.
class ReviewPromptSession {
  static const launchCountKey = 'review_prompt_launch_count';
  static const delay = Duration(minutes: 2);
  bool _started = false;
  bool _suppressed = false;
  Timer? _timer;

  void schedule(Future<void> Function() showPrompt) {
    if (_started) return;
    _started = true;
    final eligible = _registerLaunch();
    _timer = Timer(delay, () async {
      if (!await eligible || _suppressed) return;
      // Consume this session before opening a dialog or awaiting a store call.
      _suppressed = true;
      await showPrompt();
    });
  }

  Future<bool> _registerLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(launchCountKey) ?? 0) + 1;
      final saved = await prefs.setInt(launchCountKey, count);
      return saved && count.isEven;
    } catch (error) {
      debugPrint('[REVIEW] Could not record app launch: $error');
      return false;
    }
  }

  /// Also suppress automatic requests after a manual rating in this session.
  void cancel() {
    _suppressed = true;
    _timer?.cancel();
  }
}
