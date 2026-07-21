import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single source of truth for how Quran (Arabic) ayah text is styled, so the
/// reader, translation view and quiz all render ayahs identically.
///
/// The script (`uthmani` / `indopak`) and size (`Small`/`Medium`/`Large`) are
/// the same preferences set in the translation settings sheet.
class QuranArabicStyle {
  static const _scriptKey = 'arabic_script';
  static const _fontSizeKey = 'font_size';

  static const Map<String, double> _ayahSizes = {
    'Small': 18.0,
    'Medium': 22.0,
    'Large': 26.0,
  };

  static String fontFamily(String script) =>
      script == 'indopak' ? 'IndoPak' : 'Uthmani2';

  static double ayahSize(String fontSize) => _ayahSizes[fontSize] ?? 22.0;

  static TextStyle ayah({
    required String script,
    required String fontSize,
    required Color color,
    double sizeBoost = 0,
    double height = 1.8,
  }) {
    return TextStyle(
      fontFamily: fontFamily(script),
      fontSize: ayahSize(fontSize) + sizeBoost,
      height: height,
      color: color,
    );
  }

  /// The user's saved Arabic script / size, shared with the translation view.
  static Future<({String script, String fontSize})> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      script: prefs.getString(_scriptKey) ?? 'uthmani',
      fontSize: prefs.getString(_fontSizeKey) ?? 'Medium',
    );
  }
}
