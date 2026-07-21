import 'dart:math';

import 'package:mushaf_two_page/models/quran_audio.dart' show quranAyahCounts;
import 'package:mushaf_two_page/utils/arabic_text_manager.dart';

import 'quiz_models.dart';

/// Turns a [QuizConfig] into concrete questions. The scope/answer maths are pure
/// functions (unit-tested); only [generate] touches the asset databases.
class QuizGenerator {
  /// Every (surah, ayah) inside the scope that has at least one following ayah
  /// in the same surah — i.e. a valid place to ask "what comes next?".
  static List<({int surah, int ayah})> eligiblePositions(QuizConfig config) {
    final spans = [for (final r in config.ranges) r.globalSpan()];
    final result = <({int surah, int ayah})>[];
    var gi = 0;
    for (var surah = 1; surah <= 114; surah++) {
      final count = quranAyahCounts[surah - 1];
      for (var ayah = 1; ayah <= count; ayah++, gi++) {
        if (ayah == count) continue; // nothing follows in this surah
        for (final s in spans) {
          if (gi >= s.start && gi <= s.end) {
            result.add((surah: surah, ayah: ayah));
            break;
          }
        }
      }
    }
    return result;
  }

  /// The ayah numbers answering a prompt: the next [n] within the surah, clamped
  /// to the surah's final ayah.
  static List<int> answerAyahNumbers(int surah, int startAyah, int n) {
    final count = quranAyahCounts[surah - 1];
    final end = (startAyah + n).clamp(0, count);
    return [for (var a = startAyah + 1; a <= end; a++) a];
  }

  /// Sample distinct eligible positions (fewer if the scope is small) and load
  /// their Arabic text in the given [script].
  static Future<List<QuizQuestion>> generate(
    QuizConfig config, {
    required String script,
    Random? random,
  }) async {
    final rng = random ?? Random();
    final eligible = eligiblePositions(config);
    if (eligible.isEmpty) return [];

    final picks = ([...eligible]..shuffle(rng))
        .take(config.questionCount)
        .toList();

    final textBySurah = <int, Map<int, String>>{};
    for (final s in picks.map((p) => p.surah).toSet()) {
      textBySurah[s] = await ArabicTextManager.getSurah(s, source: script);
    }

    return [
      for (final p in picks)
        _buildQuestion(p.surah, p.ayah, config.answerLength, textBySurah[p.surah]!),
    ];
  }

  static QuizQuestion _buildQuestion(
    int surah,
    int startAyah,
    int answerLength,
    Map<int, String> text,
  ) {
    final answerNums = answerAyahNumbers(surah, startAyah, answerLength);
    return QuizQuestion(
      surah: surah,
      startAyah: startAyah,
      promptText: text[startAyah] ?? '',
      answerAyahs: answerNums,
      answerTexts: [for (final a in answerNums) text[a] ?? ''],
    );
  }
}
