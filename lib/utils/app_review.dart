import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';

/// Handles native in-app review prompts for Android and iOS.
///
/// Android uses the Google Play In-App Review API. iOS uses StoreKit review
/// APIs. Both platforms decide whether the prompt is actually shown.
class AppReview {
  /// Required only for opening the App Store listing on iOS.
  /// Set this to the numeric Apple ID once the app is live in App Store Connect.
  static const String? _iosAppStoreId = null;

  static final _review = InAppReview.instance;

  /// Shows a reliable Play Store prompt three minutes after an Android launch.
  /// StoreKit remains native on iOS until an App Store listing ID is supplied.
  static Timer schedulePromptAfterOpen(
    BuildContext? Function() contextProvider,
  ) {
    return Timer(const Duration(minutes: 3), () async {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final context = contextProvider();
        if (context != null && context.mounted) {
          await _showPlayStorePrompt(context);
        }
        return;
      }
      await _requestNativeReview();
    });
  }

  /// Call directly when the user taps "Rate / Review" in settings.
  static Future<void> requestFromUser() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _openStoreListingIfPossible();
      return;
    }
    await _requestNativeReview();
  }

  static Future<void> _showPlayStorePrompt(BuildContext context) async {
    final openStore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enjoying the Quran app?'),
        content: const Text(
          'Would you like to rate it on Google Play? It only takes a moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.star_rounded),
            label: const Text('Rate on Play Store'),
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
