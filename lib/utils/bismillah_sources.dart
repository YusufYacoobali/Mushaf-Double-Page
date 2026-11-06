import '../models/quran_audio.dart';
import '../logic/audio_repository.dart' show AudioFailure, AudioFailureKind;

/// Source-directory audit: docs/v5-validation.md. Do not guess 000000.mp3,
/// substitute another voice, or infer embedded Bismillah from a missing file.
/// SSS000 files are separate introductions in these EveryAyah collections.
abstract final class BismillahSources {
  static const separateSurahIntroductions = {
    'alafasy',
    'sudais',
    'abdul_basit_murattal',
    'abdul_basit_mujawwad',
    'shaatree',
    'ajamy',
    'muaiqly',
    'minshawy',
    'minshawy_mujawwad',
    'hudhaify',
    'muhammad_ayyoub',
    'nasser_qatami',
    'yasser_dussary',
    'shuraym',
    'fares_abbad',
    'abdullah_juhany',
    'ali_jaber',
    'salah_bukhatir',
  };
  static const unverified = {'husary', 'hani_rifai', 'abdullah_basfar'};

  // Ghamdi supplies a named standalone file; 002000 is absent. Basfar's
  // collection is mixed: only these separately listed openings are enabled.
  static const standalone = {'saad_ghamdi': 'bismillah.mp3'};
  static const partial = {
    'abdullah_basfar': {112, 113, 114},
  };

  static String filename(Reciter reciter, int surah) {
    final named = standalone[reciter.id];
    if (named != null) return named;
    if (!separateSurahIntroductions.contains(reciter.id) &&
        !(partial[reciter.id]?.contains(surah) ?? false)) {
      throw AudioFailure(
        AudioFailureKind.unavailable,
        'A separate Bismillah has not been verified for ${reciter.name} in surah $surah. '
        'The opening ayah may already include it. Retry, continue without a '
        'separate introduction, or stop. Your reciter will not be changed.',
      );
    }
    return '${surah.toString().padLeft(3, '0')}000.mp3';
  }
}
