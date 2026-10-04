import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JourneyStats {
  const JourneyStats({
    this.pagesOpened = 0,
    this.ayahsListened = 0,
    this.translationsRead = 0,
    this.readingSeconds = 0,
    this.listeningSeconds = 0,
    this.appSeconds = 0,
    this.activeDays = 0,
    this.surahsListened = 0,
    this.uniqueAyahs = 0,
    this.bestStreak = 0,
    this.since,
  });
  final int pagesOpened, ayahsListened, translationsRead, readingSeconds;
  final int listeningSeconds,
      appSeconds,
      activeDays,
      surahsListened,
      uniqueAyahs,
      bestStreak;
  final DateTime? since;
}

/// Device-local totals. Serialized updates prevent simultaneous audio/reading
/// activity from overwriting one another. No historical totals are invented.
abstract final class JourneyStore {
  static const storageKey = 'quran_journey_v1';
  static Future<void>? _pending;
  static Map<String, dynamic> _read(SharedPreferences prefs) {
    final raw = prefs.getString(storageKey);
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static Future<void> _update(void Function(Map<String, dynamic>) change) {
    final operation = (_pending ?? Future<void>.value())
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          final data = _read(prefs);
          data.putIfAbsent('since', () => DateTime.now().toIso8601String());
          data.putIfAbsent(
            'bestStreak',
            () => prefs.getInt('reading_streak') ?? 0,
          );
          change(data);
          await prefs.setString(storageKey, jsonEncode(data));
        })
        .catchError((Object error) {
          debugPrint('[JOURNEY] Could not save activity: $error');
        });
    _pending = operation;
    return operation.whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
  }

  static void _add(Map<String, dynamic> data, String key, int amount) =>
      data[key] = (data[key] as int? ?? 0) + amount;
  static void _include(Map<String, dynamic> data, String key, String value) =>
      data[key] = {
        ...List<String>.from(data[key] as List? ?? []),
        value,
      }.toList();

  static Future<void> recordDay({DateTime? now, int streak = 0}) =>
      _update((data) {
        final day = now ?? DateTime.now();
        _include(data, 'days', '${day.year}-${day.month}-${day.day}');
        final best = data['bestStreak'] as int? ?? 0;
        if (streak > best) data['bestStreak'] = streak;
      });
  static Future<void> recordPages(int count) => count <= 0
      ? Future.value()
      : _update((data) => _add(data, 'pages', count));
  static Future<void> recordTranslation() =>
      _update((data) => _add(data, 'translations', 1));
  static Future<void> recordListen(String verse) => _update((data) {
    _add(data, 'listens', 1);
    _include(data, 'ayahs', verse);
    _include(data, 'surahs', verse.split(':').first);
  });
  static Future<void> recordTime({
    int reading = 0,
    int listening = 0,
    int app = 0,
  }) => reading <= 0 && listening <= 0 && app <= 0
      ? Future.value()
      : _update((data) {
          if (reading > 0) _add(data, 'readingSeconds', reading);
          if (listening > 0) _add(data, 'listeningSeconds', listening);
          if (app > 0) _add(data, 'appSeconds', app);
        });

  static Future<JourneyStats> load() async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    final d = _read(prefs);
    return JourneyStats(
      pagesOpened: d['pages'] as int? ?? 0,
      ayahsListened: d['listens'] as int? ?? 0,
      translationsRead: d['translations'] as int? ?? 0,
      readingSeconds: d['readingSeconds'] as int? ?? 0,
      listeningSeconds: d['listeningSeconds'] as int? ?? 0,
      appSeconds: d['appSeconds'] as int? ?? 0,
      activeDays: (d['days'] as List? ?? []).length,
      surahsListened: (d['surahs'] as List? ?? []).length,
      uniqueAyahs: (d['ayahs'] as List? ?? []).length,
      bestStreak:
          d['bestStreak'] as int? ?? prefs.getInt('reading_streak') ?? 0,
      since: DateTime.tryParse(d['since'] as String? ?? ''),
    );
  }
}
