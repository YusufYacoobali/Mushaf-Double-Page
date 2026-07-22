import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';

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

  /// Android prompts after three minutes; iOS prompts after five minutes.
  static Timer schedulePromptAfterOpen(
    BuildContext? Function() contextProvider,
  ) {
    final delay = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? const Duration(minutes: 5)
        : const Duration(minutes: 3);
    return Timer(delay, () async {
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
    });
  }

  /// Call directly when the user taps "Rate / Review" in settings.
  static Future<void> requestFromUser() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await _openStoreListingIfPossible();
      return;
    }
    await _requestNativeReview();
  }

  static Future<void> _showStorePrompt(
    BuildContext context, {
    required bool isIos,
  }) async {
    final openStore = await showDialog<bool>(
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

    if (openStore == true) await _openStoreListingIfPossible();
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
