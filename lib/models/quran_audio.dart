import 'package:mushaf_two_page/utils/surah_mapper.dart';

enum AudioRepeatMode { range, ayah }

enum AudioSourceMode { range, surah }

class Reciter {
  final String id;
  final String name;
  final String folder;
  final String bitrate;

  const Reciter({
    required this.id,
    required this.name,
    required this.folder,
    required this.bitrate,
  });
}

class AudioVerse {
  final int surah;
  final int ayah;
  final int cycle;

  const AudioVerse({
    required this.surah,
    required this.ayah,
    required this.cycle,
  });
}

class AudioPlaybackPlan {
  final Reciter reciter;
  final int surah;
  final int fromAyah;
  final int toAyah;
  final int? repeatCount;
  final AudioRepeatMode repeatMode;
  final AudioSourceMode sourceMode;

  const AudioPlaybackPlan({
    required this.reciter,
    required this.surah,
    required this.fromAyah,
    required this.toAyah,
    required this.repeatCount,
    required this.repeatMode,
    required this.sourceMode,
  });

  SurahRange get surahInfo => quranSurahs[surah - 1];
  int get ayahCount => quranAyahCounts[surah - 1];
  int get effectiveFromAyah =>
      sourceMode == AudioSourceMode.surah ? 1 : fromAyah;
  int get effectiveToAyah =>
      sourceMode == AudioSourceMode.surah ? ayahCount : toAyah;
  int get uniqueAyahCount => effectiveToAyah - effectiveFromAyah + 1;
  bool get infiniteRepeat => repeatCount == null;
  int get visibleRepeatCount => repeatCount ?? 1;
  int get totalPlaybackItems => uniqueAyahCount * visibleRepeatCount;
  String get rangeLabel =>
      sourceMode == AudioSourceMode.surah ? 'Full surah' : '$fromAyah-$toAyah';
  String get repeatLabel => infiniteRepeat ? '\u221e' : '${repeatCount}x';

  bool matches(AudioPlaybackPlan? other) {
    return other != null &&
        other.reciter.id == reciter.id &&
        other.surah == surah &&
        other.effectiveFromAyah == effectiveFromAyah &&
        other.effectiveToAyah == effectiveToAyah &&
        other.repeatCount == repeatCount &&
        other.repeatMode == repeatMode &&
        other.sourceMode == sourceMode;
  }

  List<AudioVerse> uniqueVerses() {
    return [
      for (var ayah = effectiveFromAyah; ayah <= effectiveToAyah; ayah++)
        AudioVerse(surah: surah, ayah: ayah, cycle: 1),
    ];
  }

  List<AudioVerse> playbackVerses() {
    final verses = <AudioVerse>[];

    if (repeatMode == AudioRepeatMode.range) {
      for (var cycle = 1; cycle <= visibleRepeatCount; cycle++) {
        for (var ayah = effectiveFromAyah; ayah <= effectiveToAyah; ayah++) {
          verses.add(AudioVerse(surah: surah, ayah: ayah, cycle: cycle));
        }
      }
      return verses;
    }

    for (var ayah = effectiveFromAyah; ayah <= effectiveToAyah; ayah++) {
      for (var cycle = 1; cycle <= visibleRepeatCount; cycle++) {
        verses.add(AudioVerse(surah: surah, ayah: ayah, cycle: cycle));
      }
    }

    return verses;
  }
}

const List<Reciter> quranReciters = [
  Reciter(
    id: 'alafasy',
    name: 'Mishary Alafasy',
    folder: 'Alafasy_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'sudais',
    name: 'Abdurrahman As-Sudais',
    folder: 'Abdurrahmaan_As-Sudais_192kbps',
    bitrate: '192kbps',
  ),
  Reciter(
    id: 'abdul_basit_murattal',
    name: 'Abdul Basit Murattal',
    folder: 'Abdul_Basit_Murattal_192kbps',
    bitrate: '192kbps',
  ),
  Reciter(
    id: 'abdul_basit_mujawwad',
    name: 'Abdul Basit Mujawwad',
    folder: 'Abdul_Basit_Mujawwad_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'husary',
    name: 'Mahmoud Khalil Al-Husary',
    folder: 'Husary_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'shaatree',
    name: 'Abu Bakr Ash-Shaatree',
    folder: 'Abu_Bakr_Ash-Shaatree_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'ajamy',
    name: 'Ahmed Al-Ajamy',
    folder: 'ahmed_ibn_ali_al_ajamy_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'muaiqly',
    name: 'Maher Al Muaiqly',
    folder: 'MaherAlMuaiqly128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'minshawy',
    name: 'Mohamed Siddiq Al-Minshawy',
    folder: 'Minshawy_Murattal_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'hani_rifai',
    name: 'Hani Rifai',
    folder: 'Hani_Rifai_192kbps',
    bitrate: '192kbps',
  ),
  Reciter(
    id: 'hudhaify',
    name: 'Ali Al-Hudhaify',
    folder: 'Hudhaify_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'muhammad_ayyoub',
    name: 'Muhammad Ayyoub',
    folder: 'Muhammad_Ayyoub_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'nasser_qatami',
    name: 'Nasser Al Qatami',
    folder: 'Nasser_Alqatami_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'yasser_dussary',
    name: 'Yasser Ad-Dussary',
    folder: 'Yasser_Ad-Dussary_128kbps',
    bitrate: '128kbps',
  ),
  Reciter(
    id: 'shuraym',
    name: 'Saud Ash-Shuraym',
    folder: 'Saood_ash-Shuraym_128kbps',
    bitrate: '128kbps',
  ),
];

const List<int> quranAyahCounts = [
  7,
  286,
  200,
  176,
  120,
  165,
  206,
  75,
  129,
  109,
  123,
  111,
  43,
  52,
  99,
  128,
  111,
  110,
  98,
  135,
  112,
  78,
  118,
  64,
  77,
  227,
  93,
  88,
  69,
  60,
  34,
  30,
  73,
  54,
  45,
  83,
  182,
  88,
  75,
  85,
  54,
  53,
  89,
  59,
  37,
  35,
  38,
  29,
  18,
  45,
  60,
  49,
  62,
  55,
  78,
  96,
  29,
  22,
  24,
  13,
  14,
  11,
  11,
  18,
  12,
  12,
  30,
  52,
  52,
  44,
  28,
  28,
  20,
  56,
  40,
  31,
  50,
  40,
  46,
  42,
  29,
  19,
  36,
  25,
  22,
  17,
  19,
  26,
  30,
  20,
  15,
  21,
  11,
  8,
  8,
  19,
  5,
  8,
  8,
  11,
  11,
  8,
  3,
  9,
  5,
  4,
  7,
  3,
  6,
  3,
  5,
  4,
  5,
  6,
];

const List<SurahRange> quranSurahs = [
  SurahRange(1, 1, 1, 'Al-Fatiha', 'The Opening'),
  SurahRange(2, 1, 1, 'Al-Baqarah', 'The Cow'),
  SurahRange(3, 1, 1, 'Aal-E-Imran', 'Family of Imran'),
  SurahRange(4, 1, 1, 'An-Nisa', 'The Women'),
  SurahRange(5, 1, 1, 'Al-Maidah', 'The Table Spread'),
  SurahRange(6, 1, 1, 'Al-Anam', 'The Cattle'),
  SurahRange(7, 1, 1, 'Al-Araf', 'The Heights'),
  SurahRange(8, 1, 1, 'Al-Anfal', 'The Spoils of War'),
  SurahRange(9, 1, 1, 'At-Tawbah', 'The Repentance'),
  SurahRange(10, 1, 1, 'Yunus', 'Jonah'),
  SurahRange(11, 1, 1, 'Hud', 'Hud'),
  SurahRange(12, 1, 1, 'Yusuf', 'Joseph'),
  SurahRange(13, 1, 1, 'Ar-Rad', 'The Thunder'),
  SurahRange(14, 1, 1, 'Ibrahim', 'Abraham'),
  SurahRange(15, 1, 1, 'Al-Hijr', 'The Rocky Tract'),
  SurahRange(16, 1, 1, 'An-Nahl', 'The Bee'),
  SurahRange(17, 1, 1, 'Al-Isra', 'The Night Journey'),
  SurahRange(18, 1, 1, 'Al-Kahf', 'The Cave'),
  SurahRange(19, 1, 1, 'Maryam', 'Mary'),
  SurahRange(20, 1, 1, 'Taha', 'Ta-Ha'),
  SurahRange(21, 1, 1, 'Al-Anbiya', 'The Prophets'),
  SurahRange(22, 1, 1, 'Al-Hajj', 'The Pilgrimage'),
  SurahRange(23, 1, 1, 'Al-Muminun', 'The Believers'),
  SurahRange(24, 1, 1, 'An-Nur', 'The Light'),
  SurahRange(25, 1, 1, 'Al-Furqan', 'The Criterion'),
  SurahRange(26, 1, 1, 'Ash-Shuara', 'The Poets'),
  SurahRange(27, 1, 1, 'An-Naml', 'The Ant'),
  SurahRange(28, 1, 1, 'Al-Qasas', 'The Stories'),
  SurahRange(29, 1, 1, 'Al-Ankabut', 'The Spider'),
  SurahRange(30, 1, 1, 'Ar-Rum', 'The Romans'),
  SurahRange(31, 1, 1, 'Luqman', 'Luqman'),
  SurahRange(32, 1, 1, 'As-Sajda', 'The Prostration'),
  SurahRange(33, 1, 1, 'Al-Ahzab', 'The Confederates'),
  SurahRange(34, 1, 1, 'Saba', 'Sheba'),
  SurahRange(35, 1, 1, 'Fatir', 'Originator'),
  SurahRange(36, 1, 1, 'Ya-Sin', 'Ya-Sin'),
  SurahRange(37, 1, 1, 'As-Saffat', 'Those Who Set the Ranks'),
  SurahRange(38, 1, 1, 'Sad', 'Sad'),
  SurahRange(39, 1, 1, 'Az-Zumar', 'The Groups'),
  SurahRange(40, 1, 1, 'Ghafir', 'The Forgiver'),
  SurahRange(41, 1, 1, 'Fussilat', 'Explained in Detail'),
  SurahRange(42, 1, 1, 'Ash-Shura', 'Consultation'),
  SurahRange(43, 1, 1, 'Az-Zukhruf', 'Gold Ornaments'),
  SurahRange(44, 1, 1, 'Ad-Dukhan', 'The Smoke'),
  SurahRange(45, 1, 1, 'Al-Jathiya', 'The Kneeling'),
  SurahRange(46, 1, 1, 'Al-Ahqaf', 'The Wind-Curved Sandhills'),
  SurahRange(47, 1, 1, 'Muhammad', 'Muhammad'),
  SurahRange(48, 1, 1, 'Al-Fath', 'The Victory'),
  SurahRange(49, 1, 1, 'Al-Hujurat', 'The Rooms'),
  SurahRange(50, 1, 1, 'Qaf', 'Qaf'),
  SurahRange(51, 1, 1, 'Adh-Dhariyat', 'The Scatterers'),
  SurahRange(52, 1, 1, 'At-Tur', 'The Mount'),
  SurahRange(53, 1, 1, 'An-Najm', 'The Star'),
  SurahRange(54, 1, 1, 'Al-Qamar', 'The Moon'),
  SurahRange(55, 1, 1, 'Ar-Rahman', 'The Most Merciful'),
  SurahRange(56, 1, 1, 'Al-Waqia', 'The Inevitable'),
  SurahRange(57, 1, 1, 'Al-Hadid', 'The Iron'),
  SurahRange(58, 1, 1, 'Al-Mujadila', 'The Pleading Woman'),
  SurahRange(59, 1, 1, 'Al-Hashr', 'The Exile'),
  SurahRange(60, 1, 1, 'Al-Mumtahina', 'She That Is To Be Examined'),
  SurahRange(61, 1, 1, 'As-Saff', 'The Ranks'),
  SurahRange(62, 1, 1, 'Al-Jumuah', 'The Congregation'),
  SurahRange(63, 1, 1, 'Al-Munafiqun', 'The Hypocrites'),
  SurahRange(64, 1, 1, 'At-Taghabun', 'Mutual Loss and Gain'),
  SurahRange(65, 1, 1, 'At-Talaq', 'Divorce'),
  SurahRange(66, 1, 1, 'At-Tahrim', 'The Prohibition'),
  SurahRange(67, 1, 1, 'Al-Mulk', 'The Sovereignty'),
  SurahRange(68, 1, 1, 'Al-Qalam', 'The Pen'),
  SurahRange(69, 1, 1, 'Al-Haaqqa', 'The Reality'),
  SurahRange(70, 1, 1, 'Al-Maarij', 'The Ascending Stairways'),
  SurahRange(71, 1, 1, 'Nuh', 'Noah'),
  SurahRange(72, 1, 1, 'Al-Jinn', 'The Jinn'),
  SurahRange(73, 1, 1, 'Al-Muzzammil', 'The Enshrouded One'),
  SurahRange(74, 1, 1, 'Al-Muddathir', 'The Cloaked One'),
  SurahRange(75, 1, 1, 'Al-Qiyama', 'The Resurrection'),
  SurahRange(76, 1, 1, 'Al-Insan', 'Man'),
  SurahRange(77, 1, 1, 'Al-Mursalat', 'The Emissaries'),
  SurahRange(78, 1, 1, 'An-Naba', 'The Tidings'),
  SurahRange(79, 1, 1, 'An-Naziat', 'Those Who Drag Forth'),
  SurahRange(80, 1, 1, 'Abasa', 'He Frowned'),
  SurahRange(81, 1, 1, 'At-Takwir', 'The Overthrowing'),
  SurahRange(82, 1, 1, 'Al-Infitar', 'The Cleaving'),
  SurahRange(83, 1, 1, 'Al-Mutaffifin', 'Defrauding'),
  SurahRange(84, 1, 1, 'Al-Inshiqaq', 'The Splitting Open'),
  SurahRange(85, 1, 1, 'Al-Buruj', 'The Constellations'),
  SurahRange(86, 1, 1, 'At-Tariq', 'The Morning Star'),
  SurahRange(87, 1, 1, 'Al-Ala', 'The Most High'),
  SurahRange(88, 1, 1, 'Al-Ghashiya', 'The Overwhelming'),
  SurahRange(89, 1, 1, 'Al-Fajr', 'The Dawn'),
  SurahRange(90, 1, 1, 'Al-Balad', 'The City'),
  SurahRange(91, 1, 1, 'Ash-Shams', 'The Sun'),
  SurahRange(92, 1, 1, 'Al-Layl', 'The Night'),
  SurahRange(93, 1, 1, 'Ad-Duha', 'The Morning Brightness'),
  SurahRange(94, 1, 1, 'Ash-Sharh', 'The Relief'),
  SurahRange(95, 1, 1, 'At-Tin', 'The Fig'),
  SurahRange(96, 1, 1, 'Al-Alaq', 'The Clot'),
  SurahRange(97, 1, 1, 'Al-Qadr', 'The Power'),
  SurahRange(98, 1, 1, 'Al-Bayyina', 'The Clear Proof'),
  SurahRange(99, 1, 1, 'Az-Zalzalah', 'The Earthquake'),
  SurahRange(100, 1, 1, 'Al-Adiyat', 'The Chargers'),
  SurahRange(101, 1, 1, 'Al-Qaria', 'The Calamity'),
  SurahRange(102, 1, 1, 'At-Takathur', 'Rivalry In Worldly Increase'),
  SurahRange(103, 1, 1, 'Al-Asr', 'The Time'),
  SurahRange(104, 1, 1, 'Al-Humazah', 'The Slanderer'),
  SurahRange(105, 1, 1, 'Al-Fil', 'The Elephant'),
  SurahRange(106, 1, 1, 'Quraish', 'Quraysh'),
  SurahRange(107, 1, 1, 'Al-Maun', 'Small Kindnesses'),
  SurahRange(108, 1, 1, 'Al-Kawthar', 'Abundance'),
  SurahRange(109, 1, 1, 'Al-Kafirun', 'The Disbelievers'),
  SurahRange(110, 1, 1, 'An-Nasr', 'Divine Support'),
  SurahRange(111, 1, 1, 'Al-Masad', 'The Palm Fiber'),
  SurahRange(112, 1, 1, 'Al-Ikhlas', 'Sincerity'),
  SurahRange(113, 1, 1, 'Al-Falaq', 'The Daybreak'),
  SurahRange(114, 1, 1, 'An-Nas', 'Mankind'),
];
