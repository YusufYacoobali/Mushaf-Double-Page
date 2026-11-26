import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioPreferencesData {
  final String reciterId;
  final int surah;
  final int fromAyah;
  final int toAyah;
  final int? repeatCount;
  final AudioRepeatMode repeatMode;
  final AudioSourceMode sourceMode;
  final List<int> surahQueue;

  const AudioPreferencesData({
    required this.reciterId,
    required this.surah,
    required this.fromAyah,
    required this.toAyah,
    required this.repeatCount,
    required this.repeatMode,
    required this.sourceMode,
    this.surahQueue = const [],
  });
}

class AudioPreferences {
  static const _configuredKey = 'audio_selection_configured';
  static const _reciterKey = 'audio_reciter';
  static const _surahKey = 'audio_surah';
  static const _fromAyahKey = 'audio_from_ayah';
  static const _toAyahKey = 'audio_to_ayah';
  static const _repeatCountKey = 'audio_repeat_count';
  static const _infiniteRepeatKey = 'audio_infinite_repeat';
  static const _repeatModeKey = 'audio_repeat_mode';
  static const _sourceModeKey = 'audio_source_mode';

  static Future<AudioPreferencesData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith('audio_original_openings_v1_'),
    )) {
      await prefs.remove(key);
    }
    if (!(prefs.getBool(_configuredKey) ?? false)) return null;

    final repeatName = prefs.getString(_repeatModeKey);
    final sourceName = prefs.getString(_sourceModeKey);
    return AudioPreferencesData(
      surahQueue: (prefs.getStringList('audio_surah_queue') ?? [])
          .map(int.tryParse)
          .whereType<int>()
          .where((s) => s >= 1 && s <= 114)
          .toSet()
          .toList(),
      reciterId: prefs.getString(_reciterKey) ?? quranReciters.first.id,
      surah: prefs.getInt(_surahKey) ?? 1,
      fromAyah: prefs.getInt(_fromAyahKey) ?? 1,
      toAyah: prefs.getInt(_toAyahKey) ?? 7,
      repeatCount: prefs.getBool(_infiniteRepeatKey) ?? false
          ? null
          : prefs.getInt(_repeatCountKey) ?? 10,
      repeatMode: AudioRepeatMode.values.firstWhere(
        (mode) => mode.name == repeatName,
        orElse: () => AudioRepeatMode.range,
      ),
      sourceMode: AudioSourceMode.values.firstWhere(
        (mode) => mode.name == sourceName,
        orElse: () => AudioSourceMode.range,
      ),
    );
  }

  static Future<void> save(AudioPreferencesData value) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(
        'audio_surah_queue',
        value.surahQueue.map((s) => '$s').toList(),
      ),
      prefs.setBool(_configuredKey, true),
      prefs.setString(_reciterKey, value.reciterId),
      prefs.setInt(_surahKey, value.surah),
      prefs.setInt(_fromAyahKey, value.fromAyah),
      prefs.setInt(_toAyahKey, value.toAyah),
      prefs.setBool(_infiniteRepeatKey, value.repeatCount == null),
      prefs.setInt(_repeatCountKey, value.repeatCount ?? 1),
      prefs.setString(_repeatModeKey, value.repeatMode.name),
      prefs.setString(_sourceModeKey, value.sourceMode.name),
    ]);
  }
}
