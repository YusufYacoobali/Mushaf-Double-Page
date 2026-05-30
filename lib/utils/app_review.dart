import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles native in-app review prompts for Android and iOS.
///
/// Android uses the Google Play In-App Review API. iOS uses StoreKit review
/// APIs. Both platforms decide whether the prompt is actually shown.
class AppReview {
  static const _kSessionCountKey = 'app_session_count';

  /// Required only for opening the App Store listing on iOS.
  /// Set this to the numeric Apple ID once the app is live in App Store Connect.
  static const String? _iosAppStoreId = null;

  /// Sessions at which we attempt an auto-prompt.
  static const _promptAtSessions = {5, 20};

  static final _review = InAppReview.instance;

  /// Call once per app session after the reader is ready.
  static Future<void> recordSessionAndMaybePrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_kSessionCountKey) ?? 0) + 1;
    await prefs.setInt(_kSessionCountKey, count);

    if (_promptAtSessions.contains(count)) {
      await _requestNativeReview();
    }
  }

  /// Call directly when the user taps "Rate / Review" in settings.
  static Future<void> requestFromUser() async {
    await _requestNativeReview();
  }

  static Future<void> _requestNativeReview() async {
    try {
      if (await _review.isAvailable()) {
        await _review.requestReview();
        return;
      }

      await _openStoreListingIfPossible();
    } catch (e) {
      debugPrint('[REVIEW] Native review request failed: $e');
      await _openStoreListingIfPossible();
    }
  }

  static Future<void> _openStoreListingIfPossible() async {
    try {
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          _iosAppStoreId == null) {
        debugPrint(
          '[REVIEW] Add the App Store numeric ID before using iOS store fallback.',
        );
        return;
      }

      await _review.openStoreListing(appStoreId: _iosAppStoreId);
    } catch (e) {
      debugPrint('[REVIEW] Store listing fallback failed: $e');
    }
  }
}
