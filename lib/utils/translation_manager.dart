import 'package:flutter/services.dart' show rootBundle;

class TranslationManager {
  static const Map<String, String> sources = {
    "Sahih Int'l": 'assets/translations/en.sahih.txt',
    'Pickthall': 'assets/translations/en.pickthall.txt',
    'Hilali': 'assets/translations/en.hilali.txt',
    'Transliteration': 'assets/translations/en.transliteration.txt',
  };

  static final Map<String, Map<int, Map<int, String>>> _cache = {};

  static Future<void> load() => loadSource("Sahih Int'l");

  static Future<void> loadSource(String source) async {
    if (_cache.containsKey(source)) return;
    final path = sources[source];
    if (path == null) return;

    final data = await rootBundle.loadString(path);
    final Map<int, Map<int, String>> surahs = {};

    for (final line in data.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('|');
      if (parts.length < 3) continue;
      final surah = int.tryParse(parts[0]) ?? 0;
      final ayah = int.tryParse(parts[1]) ?? 0;
      final text = _stripHtml(parts.skip(2).join('|'));
      surahs.putIfAbsent(surah, () => {})[ayah] = text;
    }

    _cache[source] = surahs;
  }

  static Map<int, String> getSurah(int surah, {String source = "Sahih Int'l"}) {
    return _cache[source]?[surah] ?? {};
  }

  static String _stripHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}
