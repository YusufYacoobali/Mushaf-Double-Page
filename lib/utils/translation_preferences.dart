import 'package:shared_preferences/shared_preferences.dart';

class TranslationPreferencesData {
  final List<String> translations;
  final List<String> tafseers;
  final bool showArabic;
  final String fontSize;
  final String arabicScript;

  const TranslationPreferencesData({
    required this.translations,
    required this.tafseers,
    required this.showArabic,
    required this.fontSize,
    required this.arabicScript,
  });
}

/// Shared translation-display preferences used by the full reader and the
/// compact single-ayah translation sheet.
class TranslationPreferences {
  static const _translationsKey = 'trans_selected';
  static const _tafseersKey = 'tafseer_selected';
  static const _showArabicKey = 'show_arabic';
  static const _fontSizeKey = 'font_size';
  static const _arabicScriptKey = 'arabic_script';

  static Future<TranslationPreferencesData> load() async {
    final prefs = await SharedPreferences.getInstance();
    return TranslationPreferencesData(
      translations:
          prefs.getStringList(_translationsKey) ?? ['Saheeh International'],
      tafseers: prefs.getStringList(_tafseersKey) ?? ['Tafseer Ibn Kathir'],
      showArabic: prefs.getBool(_showArabicKey) ?? true,
      fontSize: prefs.getString(_fontSizeKey) ?? 'Medium',
      arabicScript: prefs.getString(_arabicScriptKey) ?? 'uthmani',
    );
  }

  static Future<void> save(TranslationPreferencesData value) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(_translationsKey, value.translations),
      prefs.setStringList(_tafseersKey, value.tafseers),
      prefs.setBool(_showArabicKey, value.showArabic),
      prefs.setString(_fontSizeKey, value.fontSize),
      prefs.setString(_arabicScriptKey, value.arabicScript),
    ]);
  }

  static Future<void> saveSourceSelections({
    required List<String> translations,
    required List<String> tafseers,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(_translationsKey, translations),
      prefs.setStringList(_tafseersKey, tafseers),
    ]);
  }
}
