import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool isReviewLaunch(int launch) =>
    (launch >= 1 && launch <= 5) || (launch >= 15 && (launch - 15) % 10 == 0);

/// One instance lasts for the app process, including background/resume cycles.
class ReviewPromptSession with WidgetsBindingObserver {
  static const launchCountKey = 'review_prompt_launch_count';
  static const rateChosenKey = 'review_prompt_rate_chosen';
  static const delay = Duration(minutes: 2);
  bool _started = false;
  bool _suppressed = false;
  bool _observing = false;
  Timer? _timer;

  void schedule(
    Future<void> Function() showPrompt, {
    bool Function()? canShowPrompt,
  }) {
    if (_started) return;
    _started = true;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    final eligible = _registerLaunch();
    _timer = Timer(delay, () async {
      final shouldPrompt = await eligible;
      if (_suppressed) return;
      // Consume even a busy/background launch: never queue a surprise on return.
      cancel();
      if (!shouldPrompt) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if ((lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          !(canShowPrompt?.call() ?? true)) {
        return;
      }
      await showPrompt();
    });
  }

  Future<bool> _registerLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(launchCountKey) ?? 0) + 1;
      final saved = await prefs.setInt(launchCountKey, count);
      return saved &&
          !(prefs.getBool(rateChosenKey) ?? false) &&
          isReviewLaunch(count);
    } catch (error) {
      debugPrint('[REVIEW] Could not record app launch: $error');
      return false;
    }
  }

  Future<void> recordRateChoice() async {
    cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(rateChosenKey, true);
    } catch (error) {
      debugPrint('[REVIEW] Could not save Rate choice: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Includes inactive system permission prompts. Resume is never a new launch.
    if (state != AppLifecycleState.resumed) cancel();
  }

  void cancel() {
    _suppressed = true;
    _timer?.cancel();
    _timer = null;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }
}
