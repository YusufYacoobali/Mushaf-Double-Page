import 'package:flutter/services.dart' show rootBundle;

class TranslationManager {
  static Map<int, Map<int, String>> _translations = {};

  static Future<void> load() async {
    final data = await rootBundle.loadString('assets/translations/en.sahih.txt');
    _translations.clear();

    for (final line in data.split('\n')) {
      if (line.trim().isEmpty) continue;

      final parts = line.split('|');
      if (parts.length < 3) continue;

      final surah = int.tryParse(parts[0]) ?? 0;
      final ayah = int.tryParse(parts[1]) ?? 0;
      final text = parts[2];

      if (!_translations.containsKey(surah)) {
        _translations[surah] = {};
      }
      _translations[surah]![ayah] = text;
    }
  }

  static Map<int, String> getSurah(int surah) {
    return _translations[surah] ?? {};
  }
}