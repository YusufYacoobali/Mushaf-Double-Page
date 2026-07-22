import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class SurahSummarySection {
  final bool isHeading;
  final String text;
  const SurahSummarySection({required this.isHeading, required this.text});
}

class SurahSummary {
  final int surahNumber;
  final List<SurahSummarySection> sections;
  const SurahSummary({required this.surahNumber, required this.sections});
}

class SurahSummaryManager {
  static Map<int, SurahSummary>? _en;
  static Map<int, SurahSummary>? _ur;

  static Future<void> load() async {
    final enRaw = await rootBundle.loadString(
      'assets/summary/surah-info-en.json',
    );
    final urRaw = await rootBundle.loadString(
      'assets/summary/surah-info-ur.json',
    );
    _en = _parse(enRaw);
    _ur = _parse(urRaw);
  }

  static SurahSummary? get(int surah, {bool urdu = false}) =>
      (urdu ? _ur : _en)?[surah];

  static Map<int, SurahSummary> _parse(String raw) {
    final decoded = jsonDecode(raw);
    final List items = decoded is List
        ? decoded
        : (decoded as Map).values.toList();
    final result = <int, SurahSummary>{};
    for (final item in items) {
      final num = (item['surah_number'] as int?) ?? 0;
      final text = (item['text'] as String?) ?? '';
      result[num] = SurahSummary(
        surahNumber: num,
        sections: _parseSections(text),
      );
    }
    return result;
  }

  static List<SurahSummarySection> _parseSections(String html) {
    final sections = <SurahSummarySection>[];
    final h2 = RegExp(
      r'<h2[^>]*>(.*?)</h2>',
      caseSensitive: false,
      dotAll: true,
    );

    var pos = 0;
    for (final match in h2.allMatches(html)) {
      if (match.start > pos) {
        final body = _clean(html.substring(pos, match.start));
        if (body.isNotEmpty) {
          sections.add(SurahSummarySection(isHeading: false, text: body));
        }
      }
      final heading = _clean(match.group(1) ?? '');
      if (heading.isNotEmpty) {
        sections.add(SurahSummarySection(isHeading: true, text: heading));
      }
      pos = match.end;
    }
    if (pos < html.length) {
      final body = _clean(html.substring(pos));
      if (body.isNotEmpty) {
        sections.add(SurahSummarySection(isHeading: false, text: body));
      }
    }
    return sections;
  }

  static String _clean(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</(div|li)>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
