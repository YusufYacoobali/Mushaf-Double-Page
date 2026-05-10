import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class TafseerManager {
  static const Map<String, String> sources = {
    'Ibn Kathir': 'en-tafisr-ibn-kathir.db',
    'Maarif ul Quran': 'en-tafsir-maarif-ul-quran.db',
    'Al-Jalalayn': 'tafsir-al-jalalayn.db',
    'Abridged': 'abridged-explanation-of-the-quran.db',
  };

  static final Map<String, Database> _dbs = {};
  static final Map<String, Map<int, Map<int, String>>> _cache = {};

  static Future<Map<int, String>> getSurah(int surah, String source) async {
    _cache[source] ??= {};
    if (_cache[source]!.containsKey(surah)) return _cache[source]![surah]!;

    final db = await _openDb(source);
    final rows = await db.rawQuery(
      'SELECT ayah_key, text FROM tafsir WHERE ayah_key LIKE ?',
      ['$surah:%'],
    );

    final sorted = List<Map<String, Object?>>.from(rows)
      ..sort((a, b) {
        final aAyah =
            int.tryParse((a['ayah_key'] as String).split(':').last) ?? 0;
        final bAyah =
            int.tryParse((b['ayah_key'] as String).split(':').last) ?? 0;
        return aAyah.compareTo(bAyah);
      });

    final Map<int, String> result = {};
    for (final row in sorted) {
      final ayah =
          int.tryParse((row['ayah_key'] as String).split(':').last) ?? 0;
      result[ayah] = _stripHtml(row['text'] as String? ?? '');
    }

    _cache[source]![surah] = result;
    return result;
  }

  static Future<Database> _openDb(String source) async {
    if (_dbs.containsKey(source)) return _dbs[source]!;

    final filename = sources[source]!;
    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/tafseer_$filename';

    if (!File(localPath).existsSync()) {
      final data = await rootBundle.load('assets/tafseer/$filename');
      await File(localPath).writeAsBytes(data.buffer.asUint8List());
    }

    final db = await openDatabase(localPath, readOnly: true);
    _dbs[source] = db;
    return db;
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|h[1-6]|li)>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
