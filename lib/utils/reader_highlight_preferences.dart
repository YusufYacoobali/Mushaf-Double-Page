import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quran_audio.dart';

class SavedReaderHighlight {
  const SavedReaderHighlight({
    required this.mushaf,
    required this.page,
    required this.surah,
    required this.ayah,
  });
  final String mushaf;
  final int page, surah, ayah;
  String get identity => '$mushaf:$page:$surah:$ayah';
  Map<String, Object> toMap() => {
    'mushaf': mushaf,
    'page': page,
    'surah': surah,
    'ayah': ayah,
  };
}

abstract final class ReaderHighlightPreferences {
  static const storageKey = 'reader_highlight_v1';
  static Future<void>? _pending;

  static Future<void> save(SavedReaderHighlight? highlight) {
    final operation = (_pending ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (highlight == null) {
        await prefs.remove(storageKey);
      } else {
        await prefs.setString(storageKey, jsonEncode(highlight.toMap()));
      }
    });
    _pending = operation;
    return operation.whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
  }

  static Future<SavedReaderHighlight?> load(String mushaf) async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['mushaf'] != mushaf) return null;
      final page = data['page'], surah = data['surah'], ayah = data['ayah'];
      if (page is! int ||
          page < 1 ||
          surah is! int ||
          surah < 1 ||
          surah > 114 ||
          ayah is! int ||
          ayah < 1 ||
          ayah > quranAyahCounts[surah - 1]) {
        return null;
      }
      return SavedReaderHighlight(
        mushaf: mushaf,
        page: page,
        surah: surah,
        ayah: ayah,
      );
    } on FormatException {
      return null;
    }
  }
}
