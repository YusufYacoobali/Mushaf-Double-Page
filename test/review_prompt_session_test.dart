import 'package:flutter/foundation.dart';
import 'package:in_app_review_platform_interface/in_app_review_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/utils/review_prompt_session.dart';
import 'package:mushaf_two_page/utils/app_review.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('eligibility is exactly launches 1–5, then 15 and every tenth', () {
    const eligible = {1, 2, 3, 4, 5, 15, 25, 35, 45, 55};
    for (var launch = -1; launch <= 55; launch++) {
      expect(
        isReviewLaunch(launch),
        eligible.contains(launch),
        reason: 'launch $launch',
      );
    }
  });
  testWidgets('persisted launches keep the exact two-minute schedule', (
    tester,
  ) async {
    final promptedOn = <int>[];
    for (var launch = 1; launch <= 55; launch++) {
      final session = ReviewPromptSession();
      session.schedule(() async {
        promptedOn.add(launch);
      });
      await tester.pump();
      final before = promptedOn.length;
      await tester.pump(const Duration(seconds: 119));
      expect(promptedOn.length, before);
      await tester.pump(const Duration(seconds: 1));
      expect(promptedOn.length, before + (isReviewLaunch(launch) ? 1 : 0));
      session.cancel();
    }
    expect(promptedOn, [1, 2, 3, 4, 5, 15, 25, 35, 45, 55]);
    expect(
      (await SharedPreferences.getInstance()).getInt(
        ReviewPromptSession.launchCountKey,
      ),
      55,
    );
  });
  testWidgets(
    'existing counters migrate without resetting, including Not now',
    (tester) async {
      for (final previous in [5, 13, 14, 24, 34, 44, 54, 100]) {
        SharedPreferences.setMockInitialValues({
          ReviewPromptSession.launchCountKey: previous,
        });
        final session = ReviewPromptSession();
        var prompts = 0;
        session.schedule(() async {
          prompts++;
        });
        await tester.pump();
        await tester.pump(const Duration(minutes: 2));
        expect(prompts, isReviewLaunch(previous + 1) ? 1 : 0);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(ReviewPromptSession.launchCountKey), previous + 1);
        expect(prefs.getBool(ReviewPromptSession.rateChosenKey), isNull);
        session.cancel();
      }
    },
  );
  testWidgets(
    'rebuilds and repeated schedule calls cannot recount or prompt twice',
    (tester) async {
      final session = ReviewPromptSession();
      var prompts = 0;
      Future<void> show() async {
        prompts++;
      }

      session.schedule(show);
      await tester.pump(const Duration(minutes: 1));
      session.schedule(show);
      await tester.pump(const Duration(minutes: 1));
      expect(prompts, 1);
      session.schedule(show);
      await tester.pump(const Duration(minutes: 10));
      expect(prompts, 1);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          ReviewPromptSession.launchCountKey,
        ),
        1,
      );
      session.cancel();
    },
  );
  testWidgets(
    'background or a system interruption cancels this launch without a resume prompt',
    (tester) async {
      for (final state in [
        AppLifecycleState.paused,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final session = ReviewPromptSession();
        var prompts = 0;
        session.schedule(() async {
          prompts++;
        });
        await tester.pump();
        await tester.pump(const Duration(seconds: 119));
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump(const Duration(minutes: 2));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        session.schedule(() async {
          prompts++;
        });
        await tester.pump(const Duration(minutes: 5));
        expect(prompts, 0);
        session.cancel();
      }
      expect(
        (await SharedPreferences.getInstance()).getInt(
          ReviewPromptSession.launchCountKey,
        ),
        3,
      );
    },
  );
  testWidgets(
    'busy modal consumes eligibility instead of stacking or postponing',
    (tester) async {
      final observer = ReviewRouteObserver();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const AlertDialog(content: Text('Critical error')),
                ),
                child: const Text('Error'),
              ),
            ),
          ),
        ),
      );
      expect(observer.hasUncoveredPage, isTrue);
      await tester.tap(find.text('Error'));
      await tester.pumpAndSettle();
      expect(observer.hasUncoveredPage, isFalse);
      final session = ReviewPromptSession();
      var prompts = 0;
      session.schedule(() async {
        prompts++;
      }, canShowPrompt: () => observer.hasUncoveredPage);
      await tester.pump();
      await tester.pump(const Duration(minutes: 2));
      Navigator.of(tester.element(find.text('Critical error'))).pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 2));
      expect(prompts, 0);
      expect(observer.hasUncoveredPage, isTrue);
      session.cancel();
    },
  );
  testWidgets(
    'Rate choice survives a fresh process session and suppresses automatic prompts',
    (tester) async {
      final session = ReviewPromptSession();
      var prompts = 0;
      session.schedule(() async {
        prompts++;
      });
      await tester.pump();
      await session.recordRateChoice();
      await tester.pump(const Duration(minutes: 2));
      final next = ReviewPromptSession();
      next.schedule(() async {
        prompts++;
      });
      await tester.pump();
      await tester.pump(const Duration(minutes: 2));
      expect(prompts, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ReviewPromptSession.rateChosenKey), isTrue);
      expect(prefs.getInt(ReviewPromptSession.launchCountKey), 2);
      next.cancel();
    },
  );
  testWidgets('manual cancel does not disable a later eligible launch', (
    tester,
  ) async {
    final first = ReviewPromptSession();
    first.schedule(() async => fail('cancelled launch'));
    first.cancel();
    await tester.pump();
    final second = ReviewPromptSession();
    var prompts = 0;
    second.schedule(() async {
      prompts++;
    });
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    expect(prompts, 1);
    second.cancel();
  });
  testWidgets(
    'affirmative custom Rate persists and manual Settings rating stays independent',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <String>[];
      final original = InAppReviewPlatform.instance;
      final plugin = _ReviewPlatform(calls);
      InAppReviewPlatform.instance = plugin;
      addTearDown(() => InAppReviewPlatform.instance = original);
      addTearDown(AppReview.cancelScheduledPrompt);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          navigatorObservers: [AppReview.navigatorObserver],
          home: const Scaffold(body: Text('Reader')),
        ),
      );
      AppReview.schedulePromptAfterOpen(() => key.currentContext);
      await tester.pump();
      await tester.pump(const Duration(seconds: 119));
      expect(find.text('Enjoying the Quran app?'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Enjoying the Quran app?'), findsOneWidget);
      await tester.tap(find.text('Rate on Play Store'));
      await tester.pumpAndSettle();
      expect(
        (await SharedPreferences.getInstance()).getBool(
          ReviewPromptSession.rateChosenKey,
        ),
        isTrue,
      );
      expect(calls.where((c) => c == 'openStoreListing').length, 1);
      expect(plugin.lastAppStoreId, '6757914006');
      expect(calls, isNot(contains('requestReview')));
      await AppReview.requestFromUser();
      expect(calls.where((c) => c == 'openStoreListing').length, 2);
      await tester.pump(const Duration(minutes: 5));
      expect(find.text('Enjoying the Quran app?'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _ReviewPlatform extends InAppReviewPlatform {
  _ReviewPlatform(this.calls);
  final List<String> calls;
  String? lastAppStoreId;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> requestReview() async {
    calls.add('requestReview');
  }

  @override
  Future<void> openStoreListing({
    String? appStoreId,
    String? microsoftStoreId,
  }) async {
    lastAppStoreId = appStoreId;
    calls.add('openStoreListing');
  }
}
