import 'package:mushaf_two_page/models/quran_audio.dart' show quranAyahCounts;

/// A scope range is a run of surahs or a run of juz. A quiz can combine several
/// disconnected ranges.
enum QuizRangeType { surah, juz }

/// How the prompt ayah is presented.
///  - [text]: show the Arabic, audio optional.
///  - [audio]: audio only, Arabic hidden until revealed.
enum QuizPromptMode { text, audio }

/// Canonical Hafs juz start positions as (surah, ayah). Index 0 == juz 1.
const List<({int surah, int ayah})> juzStarts = [
  (surah: 1, ayah: 1),
  (surah: 2, ayah: 142),
  (surah: 2, ayah: 253),
  (surah: 3, ayah: 93),
  (surah: 4, ayah: 24),
  (surah: 4, ayah: 148),
  (surah: 5, ayah: 82),
  (surah: 6, ayah: 111),
  (surah: 7, ayah: 88),
  (surah: 8, ayah: 41),
  (surah: 9, ayah: 93),
  (surah: 11, ayah: 6),
  (surah: 12, ayah: 53),
  (surah: 15, ayah: 1),
  (surah: 17, ayah: 1),
  (surah: 18, ayah: 75),
  (surah: 21, ayah: 1),
  (surah: 23, ayah: 1),
  (surah: 25, ayah: 21),
  (surah: 27, ayah: 56),
  (surah: 29, ayah: 46),
  (surah: 33, ayah: 31),
  (surah: 36, ayah: 28),
  (surah: 39, ayah: 32),
  (surah: 41, ayah: 47),
  (surah: 46, ayah: 1),
  (surah: 51, ayah: 31),
  (surah: 58, ayah: 1),
  (surah: 67, ayah: 1),
  (surah: 78, ayah: 1),
];

/// A flat 0-based index over all 6236 ayahs in mushaf order. Used to compare and
/// span (surah, ayah) positions regardless of surah boundaries.
int globalAyahIndex(int surah, int ayah) {
  var index = 0;
  for (var s = 1; s < surah; s++) {
    index += quranAyahCounts[s - 1];
  }
  return index + (ayah - 1);
}

/// One past the last ayah (114:6) — sentinel for an exclusive upper bound.
int get _ayahCountTotal {
  var total = 0;
  for (final c in quranAyahCounts) {
    total += c;
  }
  return total;
}

class QuizRange {
  final QuizRangeType type;
  final int from; // inclusive surah/juz number
  final int to; // inclusive

  const QuizRange({required this.type, required this.from, required this.to});

  String get label {
    final kind = type == QuizRangeType.surah ? 'Surah' : 'Juz';
    return from == to ? '$kind $from' : '$kind $from–$to';
  }

  /// Inclusive global-index span [start, endInclusive] this range covers.
  ({int start, int end}) globalSpan() {
    if (type == QuizRangeType.surah) {
      final start = globalAyahIndex(from, 1);
      final end = globalAyahIndex(to, quranAyahCounts[to - 1]);
      return (start: start, end: end);
    }
    // Juz range.
    final startPos = juzStarts[from - 1];
    final start = globalAyahIndex(startPos.surah, startPos.ayah);
    final endExclusive = to < 30
        ? globalAyahIndex(juzStarts[to].surah, juzStarts[to].ayah)
        : _ayahCountTotal;
    return (start: start, end: endExclusive - 1);
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'from': from,
    'to': to,
  };

  factory QuizRange.fromJson(Map<String, dynamic> j) => QuizRange(
    type: QuizRangeType.values.byName(j['type'] as String),
    from: j['from'] as int,
    to: j['to'] as int,
  );
}

class QuizConfig {
  final List<QuizRange> ranges;
  final int questionCount;
  final int answerLength; // "next N ayahs"
  final QuizPromptMode promptMode;
  final String reciterId;

  const QuizConfig({
    required this.ranges,
    required this.questionCount,
    required this.answerLength,
    required this.promptMode,
    required this.reciterId,
  });

  String get scopeLabel => ranges.map((r) => r.label).join(', ');

  QuizConfig copyWith({
    List<QuizRange>? ranges,
    int? questionCount,
    int? answerLength,
    QuizPromptMode? promptMode,
    String? reciterId,
  }) => QuizConfig(
    ranges: ranges ?? this.ranges,
    questionCount: questionCount ?? this.questionCount,
    answerLength: answerLength ?? this.answerLength,
    promptMode: promptMode ?? this.promptMode,
    reciterId: reciterId ?? this.reciterId,
  );

  Map<String, dynamic> toJson() => {
    'ranges': [for (final r in ranges) r.toJson()],
    'questionCount': questionCount,
    'answerLength': answerLength,
    'promptMode': promptMode.name,
    'reciterId': reciterId,
  };

  factory QuizConfig.fromJson(Map<String, dynamic> j) => QuizConfig(
    ranges: [
      for (final r in (j['ranges'] as List))
        QuizRange.fromJson(r as Map<String, dynamic>),
    ],
    questionCount: j['questionCount'] as int,
    answerLength: j['answerLength'] as int,
    promptMode: QuizPromptMode.values.byName(j['promptMode'] as String),
    reciterId: j['reciterId'] as String,
  );

  static const QuizConfig defaults = QuizConfig(
    ranges: [QuizRange(type: QuizRangeType.juz, from: 30, to: 30)],
    questionCount: 10,
    answerLength: 5,
    promptMode: QuizPromptMode.text,
    reciterId: 'alafasy',
  );
}

/// A single generated question: the prompt ayah and the ayahs that follow it.
class QuizQuestion {
  final int surah;
  final int startAyah;
  final String promptText;
  final List<int> answerAyahs;
  final List<String> answerTexts;

  const QuizQuestion({
    required this.surah,
    required this.startAyah,
    required this.promptText,
    required this.answerAyahs,
    required this.answerTexts,
  });
}

class QuizHistoryEntry {
  final DateTime date;
  final String scopeLabel;
  final int total;
  final int correct;
  final int answerLength;
  final QuizPromptMode promptMode;

  const QuizHistoryEntry({
    required this.date,
    required this.scopeLabel,
    required this.total,
    required this.correct,
    required this.answerLength,
    required this.promptMode,
  });

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'scopeLabel': scopeLabel,
    'total': total,
    'correct': correct,
    'answerLength': answerLength,
    'promptMode': promptMode.name,
  };

  factory QuizHistoryEntry.fromJson(Map<String, dynamic> j) => QuizHistoryEntry(
    date: DateTime.parse(j['date'] as String),
    scopeLabel: j['scopeLabel'] as String,
    total: j['total'] as int,
    correct: j['correct'] as int,
    answerLength: j['answerLength'] as int,
    promptMode: QuizPromptMode.values.byName(j['promptMode'] as String),
  );
}
