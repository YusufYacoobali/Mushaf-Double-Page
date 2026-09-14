import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/progress/reading_progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first reading activity starts a day streak', () async {
    SharedPreferences.setMockInitialValues({});
    await ReadingProgressStore.recordReadingActivity(
      now: DateTime(2026, 7, 20),
    );

    expect(
      (await ReadingProgressStore.load(now: DateTime(2026, 7, 20))).streak,
      1,
    );
  });

  test('same-day activity does not inflate the streak', () async {
    SharedPreferences.setMockInitialValues({});
    final day = DateTime(2026, 7, 20);
    await ReadingProgressStore.recordReadingActivity(now: day);
    await ReadingProgressStore.recordReadingActivity(
      now: day.add(const Duration(hours: 6)),
    );

    expect(
      (await ReadingProgressStore.load(now: DateTime(2026, 7, 20))).streak,
      1,
    );
  });

  test('consecutive reading days extend the streak', () async {
    SharedPreferences.setMockInitialValues({});
    await ReadingProgressStore.recordReadingActivity(
      now: DateTime(2026, 7, 20),
    );
    await ReadingProgressStore.recordReadingActivity(
      now: DateTime(2026, 7, 21),
    );

    expect(
      (await ReadingProgressStore.load(now: DateTime(2026, 7, 21))).streak,
      2,
    );
  });

  test('a missed day restarts the streak', () async {
    SharedPreferences.setMockInitialValues({});
    await ReadingProgressStore.recordReadingActivity(
      now: DateTime(2026, 7, 20),
    );
    await ReadingProgressStore.recordReadingActivity(
      now: DateTime(2026, 7, 22),
    );

    expect(
      (await ReadingProgressStore.load(now: DateTime(2026, 7, 22))).streak,
      1,
    );
  });
  test(
    'daily encouragement is returned only on the first activity that day',
    () async {
      SharedPreferences.setMockInitialValues({});
      final day = DateTime(2026, 9, 14);
      expect(
        (await ReadingProgressStore.recordReadingActivity(now: day))!.streak,
        1,
      );
      expect(
        await ReadingProgressStore.recordReadingActivity(now: day),
        isNull,
      );
      expect(
        (await ReadingProgressStore.recordReadingActivity(
          now: DateTime(2026, 9, 15),
        ))!.streak,
        2,
      );
    },
  );
}
