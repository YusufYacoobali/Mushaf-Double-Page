import 'package:shared_preferences/shared_preferences.dart';
import 'journey_store.dart';

/// The user's current consecutive-day Quran reading streak.
class ReadingProgress {
  final int streak;

  const ReadingProgress({required this.streak});
}

/// Persists only daily reading activity.
class ReadingProgressStore {
  static const _streakKey = 'reading_streak';
  static const _lastActiveKey = 'reading_last_active';

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}';

  /// Records one reader session for today. Repeated page changes on the same
  /// day are a no-op; reading on consecutive calendar days extends the streak.
  static Future<ReadingProgress?> recordReadingActivity({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = now ?? DateTime.now();
    final today = _dayKey(current);
    if (prefs.getString(_lastActiveKey) == today) {
      await JourneyStore.recordDay(
        now: current,
        streak: prefs.getInt(_streakKey) ?? 0,
      );
      return null;
    }

    final yesterday = _dayKey(
      DateTime(current.year, current.month, current.day - 1),
    );
    final previousStreak = prefs.getInt(_streakKey) ?? 0;
    final streak = prefs.getString(_lastActiveKey) == yesterday
        ? (prefs.getInt(_streakKey) ?? 0) + 1
        : 1;
    await prefs.setInt(_streakKey, streak);
    await prefs.setString(_lastActiveKey, today);
    await JourneyStore.recordDay(
      now: current,
      streak: streak > previousStreak ? streak : previousStreak,
    );
    return ReadingProgress(streak: streak);
  }

  static Future<ReadingProgress> load({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = now ?? DateTime.now();
    final last = prefs.getString(_lastActiveKey);
    final active =
        last == _dayKey(current) ||
        last == _dayKey(DateTime(current.year, current.month, current.day - 1));
    return ReadingProgress(streak: active ? prefs.getInt(_streakKey) ?? 0 : 0);
  }
}
