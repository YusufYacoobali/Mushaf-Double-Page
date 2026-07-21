import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'quiz_models.dart';

/// Persists quiz history and the last-used config (to pre-fill setup).
class QuizHistoryStore {
  static const _historyKey = 'quiz_history';
  static const _lastConfigKey = 'quiz_last_config';
  static const _maxEntries = 50;

  static Future<List<QuizHistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey) ?? const [];
    final entries = <QuizHistoryEntry>[];
    for (final s in raw) {
      try {
        entries.add(QuizHistoryEntry.fromJson(jsonDecode(s)));
      } catch (_) {
        // Skip any corrupt entry rather than failing the whole list.
      }
    }
    return entries;
  }

  static Future<void> add(QuizHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey) ?? <String>[];
    raw.insert(0, jsonEncode(entry.toJson()));
    if (raw.length > _maxEntries) raw.removeRange(_maxEntries, raw.length);
    await prefs.setStringList(_historyKey, raw);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  static Future<QuizConfig?> loadLastConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastConfigKey);
    if (raw == null) return null;
    try {
      return QuizConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLastConfig(QuizConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastConfigKey, jsonEncode(config.toJson()));
  }
}
