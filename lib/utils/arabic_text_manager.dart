import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ArabicTextManager {
  static Database? _db;
  static final Map<int, Map<int, String>> _cache = {};

  static Future<Map<int, String>> getSurah(int surah) async {
    if (_cache.containsKey(surah)) return _cache[surah]!;

    final db = await _openDb();
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

    _cache[surah] = result;
    return result;
  }

  static Future<Database> _openDb() async {
    if (_db != null) return _db!;

    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/arabic_uthmani.db';

    if (!File(localPath).existsSync()) {
      final data = await rootBundle.load('assets/arabic-text/uthmani.db');
      await File(localPath).writeAsBytes(data.buffer.asUint8List());
    }

    _db = await openDatabase(localPath, readOnly: true);
    return _db!;
  }
}
