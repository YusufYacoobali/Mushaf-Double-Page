import 'package:shared_preferences/shared_preferences.dart';

/// A snapshot of the user's reading progress.
class ReadingProgress {
  final int streak; // consecutive days with reading activity
  final int longestStreak;
  final int khatmCount; // completed read-throughs
  final int readPages; // distinct content pages read this khatm
  final int totalPages; // content pages in the current mushaf

  const ReadingProgress({
    required this.streak,
    required this.longestStreak,
    required this.khatmCount,
    required this.readPages,
    required this.totalPages,
  });

  double get khatmFraction =>
      totalPages == 0 ? 0 : (readPages / totalPages).clamp(0.0, 1.0);

  int get khatmPercent => (khatmFraction * 100).round();
}

/// Persists reading streak and khatm (completion) progress.
///
/// Khatm progress is tracked per mushaf as the set of distinct content pages
/// visited; finishing every content page counts as one khatm and resets the set
/// for the next read-through. The streak counts consecutive calendar days on
/// which any reading happened.
class ReadingProgressStore {
  static const _streakKey = 'reading_streak';
  static const _longestKey = 'reading_longest_streak';
  static const _lastActiveKey = 'reading_last_active'; // 'y-m-d'
  static const _khatmCountKey = 'khatm_count';

  static String _pagesKey(String mushaf) => 'khatm_pages_$mushaf';
  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Record that the user is reading [page] (a content page in
  /// [firstContent, lastContent]). Updates the streak and khatm set. Cheap to
  /// call on every page change — it no-ops when there is nothing new to store.
  static Future<void> recordPageRead(
    int page, {
    required String mushaf,
    required int firstContent,
    required int lastContent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = _dayKey(now);
    final inRange = page >= firstContent && page <= lastContent;

    final pagesKey = _pagesKey(mushaf);
    final read = (prefs.getStringList(pagesKey) ?? const []).toSet();
    final alreadyRead = !inRange || read.contains('$page');
    final streakCurrent = prefs.getString(_lastActiveKey) == today;

    if (alreadyRead && streakCurrent) return; // nothing changed

    // --- streak ---
    if (!streakCurrent) {
      final last = prefs.getString(_lastActiveKey);
      final yesterday = _dayKey(now.subtract(const Duration(days: 1)));
      final streak = last == yesterday ? (prefs.getInt(_streakKey) ?? 0) + 1 : 1;
      await prefs.setInt(_streakKey, streak);
      if (streak > (prefs.getInt(_longestKey) ?? 0)) {
        await prefs.setInt(_longestKey, streak);
      }
      await prefs.setString(_lastActiveKey, today);
    }

    // --- khatm set ---
    if (inRange && !read.contains('$page')) {
      read.add('$page');
      final total = lastContent - firstContent + 1;
      if (read.length >= total) {
        await prefs.setInt(_khatmCountKey, (prefs.getInt(_khatmCountKey) ?? 0) + 1);
        read.clear();
      }
      await prefs.setStringList(pagesKey, read.toList());
    }
  }

  static Future<ReadingProgress> load({
    required String mushaf,
    required int firstContent,
    required int lastContent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final read = prefs.getStringList(_pagesKey(mushaf)) ?? const [];
    return ReadingProgress(
      streak: prefs.getInt(_streakKey) ?? 0,
      longestStreak: prefs.getInt(_longestKey) ?? 0,
      khatmCount: prefs.getInt(_khatmCountKey) ?? 0,
      readPages: read.length,
      totalPages: lastContent - firstContent + 1,
    );
  }

  /// Reset the current khatm's read pages for a mushaf (does not touch streak or
  /// completed-khatm count).
  static Future<void> resetKhatm(String mushaf) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pagesKey(mushaf));
  }
}
