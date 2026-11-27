import 'juz_quarters.dart';
import 'page_ayah_index.dart';

({int surah, int page}) juzDestination(int juz, int quarter, String mushaf) {
  final divisions = mushaf == 'madani' ? madaniJuzQuarters : indopakJuzQuarters;
  final (surah, ayah) = divisions[juz - 1][quarter - 1];
  final page = PageAyahIndex.pageOfAyah(surah, ayah, mushaf: mushaf);
  if (page == null) throw StateError('Missing $mushaf page for $surah:$ayah');
  return (surah: surah, page: page);
}

List<JuzRange> getJuzRanges(String mushaf) {
  switch (mushaf) {
    case "madani":
      return madaniJuzRanges;
    case "indopak":
    case "indopak_tajweed":
      return indopakJuzRanges;
    default:
      return indopakJuzRanges;
  }
}

int pageFromJuz(int juz, String mushaf) {
  final ranges = getJuzRanges(mushaf);

  final entry = ranges.firstWhere(
    (e) => e.juz == juz,
    orElse: () => ranges.first,
  );

  return entry.start;
}

class JuzRange {
  final int juz;
  final int start;

  const JuzRange(this.juz, this.start);
}

const List<JuzRange> indopakJuzRanges = [
  JuzRange(1, 4),
  JuzRange(2, 31),
  JuzRange(3, 59),
  JuzRange(4, 87),
  JuzRange(5, 115),
  JuzRange(6, 143),
  JuzRange(7, 171),
  JuzRange(8, 199),
  JuzRange(9, 227),
  JuzRange(10, 255),
  JuzRange(11, 283),
  JuzRange(12, 311),
  JuzRange(13, 339),
  JuzRange(14, 367),
  JuzRange(15, 395),
  JuzRange(16, 423),
  JuzRange(17, 451),
  JuzRange(18, 479),
  JuzRange(19, 507),
  JuzRange(20, 535),
  JuzRange(21, 561),
  JuzRange(22, 589),
  JuzRange(23, 615),
  JuzRange(24, 643),
  JuzRange(25, 669),
  JuzRange(26, 699),
  JuzRange(27, 729),
  JuzRange(28, 759),
  JuzRange(29, 789),
  JuzRange(30, 821),
];

const List<JuzRange> madaniJuzRanges = [
  JuzRange(1, 4),
  JuzRange(2, 25),
  JuzRange(3, 45),
  JuzRange(4, 65),
  JuzRange(5, 85),
  JuzRange(6, 105),
  JuzRange(7, 124),
  JuzRange(8, 145),
  JuzRange(9, 165),
  JuzRange(10, 185),
  JuzRange(11, 204),
  JuzRange(12, 225),
  JuzRange(13, 245),
  JuzRange(14, 265),
  JuzRange(15, 285),
  JuzRange(16, 305),
  JuzRange(17, 325),
  JuzRange(18, 345),
  JuzRange(19, 365),
  JuzRange(20, 385),
  JuzRange(21, 405),
  JuzRange(22, 425),
  JuzRange(23, 445),
  JuzRange(24, 465),
  JuzRange(25, 485),
  JuzRange(26, 505),
  JuzRange(27, 525),
  JuzRange(28, 545),
  JuzRange(29, 565),
  JuzRange(30, 585),
];
