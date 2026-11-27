import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/translation/translation_content.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';
import 'package:mushaf_two_page/utils/translation_manager.dart';
import 'package:mushaf_two_page/utils/translation_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'spread and whole-surah modes assemble the same ordered ayah content',
    () async {
      final dir = await Directory.systemTemp.createTemp('translation-content');
      addTearDown(() => dir.delete(recursive: true));
      // Only the native SQLite queries are stubbed. Both translations and the
      // page-spanning verse boundaries come from the bundled assets.
      databaseFactory = databaseFactorySqflitePlugin;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      const sqlite = MethodChannel('com.tekartik.sqflite');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        paths,
        (_) async => dir.path,
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(sqlite, (
        call,
      ) async {
        if (call.method == 'openDatabase') return {'id': 1};
        if (call.method == 'query') {
          return {
            'columns': ['ayah', 'text'],
            'rows': [
              [2, 'Arabic fixture'],
            ],
          };
        }
        return null;
      });
      addTearDown(() {
        for (final channel in [paths, sqlite]) {
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        }
      });
      await PageAyahIndex.load();
      const sources = ['Muhammad M. Pickthall', 'Saheeh International'];
      const loader = TranslationContentLoader(
        TranslationPreferencesData(
          translations: sources,
          tafseers: [],
          showArabic: true,
          fontSize: 'Medium',
          arabicScript: 'uthmani',
        ),
      );
      final spread = await loader.loadPage('indopak', [846, 847]);
      expect(spread.whereType<TranslationHeader>().map((h) => h.range.surah), [
        103,
        104,
        105,
        106,
        107,
      ]);
      final range = getSurahRanges('indopak').firstWhere((r) => r.surah == 105);
      final whole = await loader.loadSurah(range);
      expect(whole.whereType<TranslationAyah>().map((a) => a.ayah), [
        1,
        2,
        3,
        4,
        5,
      ]);
      for (final entries in [spread, whole]) {
        final verse = entries.whereType<TranslationAyah>().singleWhere(
          (a) => a.surah == 105 && a.ayah == 2,
        );
        expect(verse.translations.keys, sources);
        expect(verse.arabic, 'Arabic fixture');
        expect(
          verse.textForSharing,
          [
            for (final s in sources)
              TranslationManager.getSurah(105, source: s)[2]!,
          ].join('\n\n'),
        );
      }
    },
  );
}
