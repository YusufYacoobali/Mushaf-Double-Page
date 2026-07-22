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

    expect((await ReadingProgressStore.load()).streak, 1);
  });

  test('same-day activity does not inflate the streak', () async {
    SharedPreferences.setMockInitialValues({});
    final day = DateTime(2026, 7, 20);
    await ReadingProgressStore.recordReadingActivity(now: day);
    await ReadingProgressStore.recordReadingActivity(
      now: day.add(const Duration(hours: 6)),
    );

    expect((await ReadingProgressStore.load()).streak, 1);
  });

  test('consecutive reading days extend the streak', () async {
    SharedPreferences.setMockInitialValues({});
    await ReadingProgressStore.recordReadingActivity(
      now: DateTime(2026, 7, 20),
    );
    await ReadingProgressStore.recordReadingActivity(
      now: DateTime(2026, 7, 21),
    );

    expect((await ReadingProgressStore.load()).streak, 2);
  });

  test('a missed day restarts the streak', () async {
    SharedPreferences.setMockInitialValues({});
    await ReadingProgressStore.recordReadingActivity(
      now: DateTime(2026, 7, 20),
    );
    await ReadingProgressStore.recordReadingActivity(
      now: DateTime(2026, 7, 22),
    );

    expect((await ReadingProgressStore.load()).streak, 1);
  });
}
