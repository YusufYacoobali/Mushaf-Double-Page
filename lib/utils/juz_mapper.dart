int juzFromPage(int page) {
  for (final j in juzRanges) {
    if (page >= j.start && page <= j.end) return j.juz;
  }
  return 1;
}

int pageFromJuz(int juz) {
  final entry = juzRanges.firstWhere(
        (e) => e.juz == juz,
    orElse: () => juzRanges.first,
  );
  return 851 - entry.start;
}

class JuzRange {
  final int juz;
  final int start;
  final int end;

  const JuzRange(this.juz, this.start, this.end);
}

const List<JuzRange> juzRanges = [
  JuzRange(1, 4, 41),
  JuzRange(2, 42, 81),
  JuzRange(3, 82, 121),
  JuzRange(4, 122, 161),
  JuzRange(5, 162, 201),
  JuzRange(6, 202, 241),
  JuzRange(7, 242, 281),
  JuzRange(8, 282, 321),
  JuzRange(9, 322, 361),
  JuzRange(10, 362, 401),
  JuzRange(11, 402, 441),
  JuzRange(12, 442, 481),
  JuzRange(13, 482, 521),
  JuzRange(14, 522, 561),
  JuzRange(15, 562, 601),
  JuzRange(16, 602, 641),
  JuzRange(17, 642, 681),
  JuzRange(18, 682, 721),
  JuzRange(19, 722, 761),
  JuzRange(20, 762, 801),
  JuzRange(21, 802, 821),
  JuzRange(22, 822, 841),
  JuzRange(23, 842, 851),
  JuzRange(24, 842, 851),
  JuzRange(25, 842, 851),
  JuzRange(26, 842, 851),
  JuzRange(27, 842, 851),
  JuzRange(28, 842, 851),
  JuzRange(29, 842, 851),
  JuzRange(30, 842, 851),
];