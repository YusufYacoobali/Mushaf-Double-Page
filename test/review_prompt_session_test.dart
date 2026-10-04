import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mushaf_two_page/utils/review_prompt_session.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'only alternate launches prompt, exactly two minutes after open',
    (tester) async {
      final promptedOn = <int>[];
      for (var launch = 1; launch <= 6; launch++) {
        final session = ReviewPromptSession();
        session.schedule(() async {
          promptedOn.add(launch);
        });
        await tester.pump();
        final before = promptedOn.length;
        await tester.pump(const Duration(seconds: 119));
        expect(promptedOn.length, before);
        await tester.pump(const Duration(seconds: 1));
        expect(promptedOn.length, before + (launch.isEven ? 1 : 0));
        session.cancel();
      }
      expect(promptedOn, [2, 4, 6]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(ReviewPromptSession.launchCountKey), 6);
    },
  );

  testWidgets(
    'rescheduling before or after dismissal never repeats or recounts a session',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        ReviewPromptSession.launchCountKey: 1,
      });
      final session = ReviewPromptSession();
      var prompts = 0;
      Future<void> showPrompt() async {
        prompts++;
      }

      session.schedule(showPrompt);
      await tester.pump(const Duration(minutes: 1));
      session.schedule(showPrompt);
      await tester.pump(const Duration(minutes: 1));
      expect(prompts, 1);
      session.schedule(showPrompt);
      await tester.pump(const Duration(minutes: 10));
      expect(prompts, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(ReviewPromptSession.launchCountKey), 2);
      session.cancel();
    },
  );

  testWidgets(
    'disposal or manual review cancels automatic prompt for the session',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        ReviewPromptSession.launchCountKey: 1,
      });
      final session = ReviewPromptSession();
      var prompts = 0;
      session.schedule(() async {
        prompts++;
      });
      session.cancel();
      await tester.pump();
      session.schedule(() async {
        prompts++;
      });
      await tester.pump(const Duration(minutes: 3));
      expect(prompts, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(ReviewPromptSession.launchCountKey), 2);
    },
  );
}
