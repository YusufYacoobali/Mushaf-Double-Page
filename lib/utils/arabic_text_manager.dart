import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ArabicTextManager {
  static final Map<String, Database> _dbs = {};
  static final Map<String, Map<int, Map<int, String>>> _cache = {};

  static Future<Map<int, String>> getSurah(int surah, {String source = 'uthmani'}) async {
    _cache[source] ??= {};
    if (_cache[source]!.containsKey(surah)) return _cache[source]![surah]!;

    final db = await _openDb(source);
    final rows = await db.query(
      'verses',
      columns: ['ayah', 'text'],
      where: 'surah = ?',
      whereArgs: [surah],
      orderBy: 'ayah',
    );

    final result = <int, String>{};
    for (final row in rows) {
      result[row['ayah'] as int] = row['text'] as String;
    }

    _cache[source]![surah] = result;
    return result;
  }

  static Future<Database> _openDb(String source) async {
    if (_dbs.containsKey(source)) return _dbs[source]!;

    final assetPath = source == 'indopak'
        ? 'assets/arabic-text/indopak.db'
        : 'assets/arabic-text/uthmani.db';
    final fileName = source == 'indopak'
        ? 'arabic_indopak.db'
        : 'arabic_uthmani.db';

    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/$fileName';

    if (!File(localPath).existsSync()) {
      final data = await rootBundle.load(assetPath);
      await File(localPath).writeAsBytes(data.buffer.asUint8List());
    }

    _dbs[source] = await openDatabase(localPath, readOnly: true);
    return _dbs[source]!;
  }
}
