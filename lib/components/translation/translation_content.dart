import '../../utils/arabic_text_manager.dart';
import '../../utils/page_ayah_index.dart';
import '../../utils/surah_mapper.dart';
import '../../utils/tafseer_manager.dart';
import '../../utils/translation_manager.dart';
import '../../utils/translation_preferences.dart';

sealed class TranslationEntry {
  const TranslationEntry();
}

class TranslationHeader extends TranslationEntry {
  const TranslationHeader(this.range);
  final SurahRange range;
}

class TranslationAyah extends TranslationEntry {
  const TranslationAyah({
    required this.surah,
    required this.ayah,
    required this.arabic,
    required this.translations,
    required this.tafseers,
  });
  final int surah;
  final int ayah;
  final String arabic;
  final Map<String, String> translations;
  final Map<String, String> tafseers;

  String get textForSharing =>
      [...translations.values, ...tafseers.values].join('\n\n');
}

class TranslationContentLoader {
  const TranslationContentLoader(this.preferences);
  final TranslationPreferencesData preferences;

  Future<void> _loadSources() async {
    for (final source in preferences.translations) {
      await TranslationManager.loadSource(source);
    }
  }

  Future<List<TranslationEntry>> loadPage(
    String mushaf,
    List<int> pages,
  ) async {
    await _loadSources();
    final ranges = getSurahRanges(mushaf);
    final items = <TranslationEntry>[];
    for (final [surah, first, last] in PageAyahIndex.segmentsForPages(
      pages,
      mushaf: mushaf,
    )) {
      final range = ranges.firstWhere(
        (r) => r.surah == surah,
        orElse: () => ranges.first,
      );
      items.add(TranslationHeader(range));
      items.addAll(
        await _loadAyahs(surah, ayahs: [for (var a = first; a <= last; a++) a]),
      );
    }
    return items;
  }

  Future<List<TranslationEntry>> loadSurah(SurahRange surah) async {
    await _loadSources();
    return [TranslationHeader(surah), ...await _loadAyahs(surah.surah)];
  }

  Future<List<TranslationAyah>> _loadAyahs(
    int surah, {
    List<int>? ayahs,
  }) async {
    final translations = {
      for (final source in preferences.translations)
        source: TranslationManager.getSurah(surah, source: source),
    };
    final tafseers = {
      for (final source in preferences.tafseers)
        source: await TafseerManager.getSurah(surah, source),
    };
    final arabic = await ArabicTextManager.getSurah(
      surah,
      source: preferences.arabicScript,
    );
    // Whole-surah mode follows the first selected translation's numbered verses.
    final numbers = ayahs ?? (translations.values.first.keys.toList()..sort());
    return [
      for (final number in numbers)
        TranslationAyah(
          surah: surah,
          ayah: number,
          arabic: arabic[number] ?? '',
          translations: {
            for (final source in translations.entries)
              source.key: source.value[number] ?? '',
          },
          tafseers: {
            for (final source in tafseers.entries)
              source.key: source.value[number] ?? '',
          },
        ),
    ];
  }
}
