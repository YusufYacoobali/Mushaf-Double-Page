import 'package:mushaf_two_page/utils/app_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'review_prompt_session.dart';

class ReviewRouteObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];
  bool get hasUncoveredPage =>
      _routes.lastOrNull is PageRoute &&
      (_routes.lastOrNull?.isCurrent ?? false);
  String? get currentPageName => _routes.lastOrNull?.settings.name;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
  }
}

/// Shows reliable app-owned review prompts and opens the platform store page.
class AppReview {
  // Android's openStoreListing resolves this exact application ID:
  // https://play.google.com/store/apps/details?id=com.quran.quran_double_page
  static const String androidApplicationId = 'com.quran.quran_double_page';
  static const String androidPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=$androidApplicationId';

  static const String _iosAppStoreId = '6757914006';
  static const String iosAppStoreUrl =
      'https://apps.apple.com/gb/app/quran-dual-page/id$_iosAppStoreId';

  static final _review = InAppReview.instance;
  static final _session = ReviewPromptSession();
  static final navigatorObserver = ReviewRouteObserver();

  /// Prompt after two minutes on launches 1–5, then 15, 25, 35, ...
  static void schedulePromptAfterOpen(
    BuildContext? Function() contextProvider, {
    bool Function()? canShowPrompt,
  }) {
    _session.schedule(
      () async {
        if (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)) {
          final context = contextProvider();
          if (context != null && context.mounted) {
            await _showStorePrompt(
              context,
              isIos: defaultTargetPlatform == TargetPlatform.iOS,
            );
          }
          return;
        }
        await _requestNativeReview();
      },
      canShowPrompt: () =>
          navigatorObserver.hasUncoveredPage && (canShowPrompt?.call() ?? true),
    );
  }

  static void cancelScheduledPrompt() => _session.cancel();

  /// Call directly when the user taps "Rate / Review" in settings.
  static Future<void> requestFromUser() async {
    await _session.recordRateChoice();
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await _openStoreListingIfPossible();
      return;
    }
    await _requestNativeReview(fromUser: true);
  }

  static Future<void> _showStorePrompt(
    BuildContext context, {
    required bool isIos,
  }) async {
    final openStore = await showDialog<bool>(
      animationStyle: AppMotion.style(context),
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enjoying the Quran app?'),
        content: Text(
          'Would you like to rate it on ${isIos ? 'the App Store' : 'Google Play'}? '
          'It only takes a moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.star_rounded),
            label: Text(isIos ? 'Rate on App Store' : 'Rate on Play Store'),
          ),
        ],
      ),
    );

    if (openStore == true) {
      await _session.recordRateChoice();
      await _openStoreListingIfPossible();
    }
  }

  static Future<void> _requestNativeReview({bool fromUser = false}) async {
    try {
      if (await _review.isAvailable()) {
        await _review.requestReview();
        return;
      }

      if (fromUser) await _openStoreListingIfPossible();
    } catch (e) {
      debugPrint('[REVIEW] Native review request failed: $e');
      if (fromUser) await _openStoreListingIfPossible();
    }
  }

  static Future<void> _openStoreListingIfPossible() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        debugPrint('[REVIEW] Opening $androidPlayStoreUrl');
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        debugPrint('[REVIEW] Opening $iosAppStoreUrl');
      }

      await _review.openStoreListing(appStoreId: _iosAppStoreId);
    } catch (e) {
      debugPrint('[REVIEW] Store listing fallback failed: $e');
    }
  }
}
