import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/quiz/quiz_generator.dart';
import 'package:mushaf_two_page/quiz/quiz_models.dart';

QuizConfig _config(List<QuizRange> ranges) => QuizConfig(
  ranges: ranges,
  questionCount: 10,
  answerLength: 5,
  promptMode: QuizPromptMode.text,
  reciterId: 'alafasy',
);

void main() {
  test('answerAyahNumbers returns the next N within the surah, clamped', () {
    expect(QuizGenerator.answerAyahNumbers(1, 1, 5), [2, 3, 4, 5, 6]);
    expect(QuizGenerator.answerAyahNumbers(1, 5, 5), [6, 7]); // Fatiha has 7
    expect(QuizGenerator.answerAyahNumbers(1, 7, 5), isEmpty); // last ayah
    expect(QuizGenerator.answerAyahNumbers(108, 1, 5), [2, 3]); // Kawthar has 3
  });

  test('juz 1 global span covers Al-Fatiha + Al-Baqarah:1-141', () {
    final span = const QuizRange(type: QuizRangeType.juz, from: 1, to: 1)
        .globalSpan();
    expect(span.start, 0); // 1:1
    expect(span.end, globalAyahIndex(2, 141)); // ends right before juz 2 (2:142)
  });

  test('eligiblePositions excludes each surah final ayah', () {
    final positions = QuizGenerator.eligiblePositions(
      _config(const [QuizRange(type: QuizRangeType.surah, from: 112, to: 114)]),
    );
    // Al-Ikhlas(4)->3, Al-Falaq(5)->4, An-Nas(6)->5 = 12 valid prompts.
    expect(positions.length, 12);
    expect(positions.contains((surah: 114, ayah: 5)), true);
    expect(positions.contains((surah: 114, ayah: 6)), false); // last ayah
    expect(positions.every((p) => p.surah >= 112 && p.surah <= 114), true);
  });

  test('juz scope resolves to verses within that juz only', () {
    final positions = QuizGenerator.eligiblePositions(
      _config(const [QuizRange(type: QuizRangeType.juz, from: 30, to: 30)]),
    );
    expect(positions.isNotEmpty, true);
    expect(positions.every((p) => p.surah >= 78), true);
    expect(positions.contains((surah: 78, ayah: 1)), true);
    expect(positions.contains((surah: 114, ayah: 6)), false);
  });

  test('multiple disconnected ranges union their positions', () {
    final positions = QuizGenerator.eligiblePositions(
      _config(const [
        QuizRange(type: QuizRangeType.surah, from: 112, to: 112), // Ikhlas: 3
        QuizRange(type: QuizRangeType.surah, from: 114, to: 114), // Nas: 5
      ]),
    );
    expect(positions.length, 8);
    expect(positions.contains((surah: 113, ayah: 1)), false); // Falaq excluded
  });

  test('QuizConfig round-trips through JSON', () {
    final config = QuizConfig(
      ranges: const [
        QuizRange(type: QuizRangeType.surah, from: 2, to: 5),
        QuizRange(type: QuizRangeType.juz, from: 29, to: 30),
      ],
      questionCount: 20,
      answerLength: 7,
      promptMode: QuizPromptMode.audio,
      reciterId: 'sudais',
    );
    final restored = QuizConfig.fromJson(config.toJson());
    expect(restored.ranges.length, 2);
    expect(restored.ranges[0].type, QuizRangeType.surah);
    expect(restored.ranges[1].from, 29);
    expect(restored.questionCount, 20);
    expect(restored.answerLength, 7);
    expect(restored.promptMode, QuizPromptMode.audio);
    expect(restored.reciterId, 'sudais');
  });
}
