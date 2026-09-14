import 'package:shared_preferences/shared_preferences.dart';

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
    if (prefs.getString(_lastActiveKey) == today) return null;

    final yesterday = _dayKey(
      DateTime(current.year, current.month, current.day - 1),
    );
    final streak = prefs.getString(_lastActiveKey) == yesterday
        ? (prefs.getInt(_streakKey) ?? 0) + 1
        : 1;
    await prefs.setInt(_streakKey, streak);
    await prefs.setString(_lastActiveKey, today);
    return ReadingProgress(streak: streak);
  }

  static Future<ReadingProgress> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ReadingProgress(streak: prefs.getInt(_streakKey) ?? 0);
  }
}
