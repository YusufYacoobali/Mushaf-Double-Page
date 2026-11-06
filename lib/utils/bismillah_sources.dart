import '../models/quran_audio.dart';
import 'bismillah_verified_sources.dart';

/// Content verification belongs to the physical recording, not its destination.
/// Each clean same-reciter source is shared by all applicable surah boundaries.
abstract final class BismillahSources {
  static final _sources = <String, AudioRecordingSource>{
    for (final row in verifiedBismillahData.entries)
      row.key: _source(row.value as Map<String, dynamic>),
  };

  static AudioRecordingSource _source(Map<String, dynamic> value) =>
      AudioRecordingSource(
        id: value['id'] as String,
        url: value['url'] as String,
        cacheFilename: value['cacheFilename'] as String,
        sha256: value['sha256'] as String,
        verification: value['verification'] as String,
      );

  static BismillahResolution resolve(Reciter reciter, int surah) {
    if (surah == 1 || surah == 9) {
      return const BismillahResolution(
        BismillahPolicyKind.notRequired,
        evidence:
            'Al-Fatihah already numbers Bismillah; At-Tawbah has no introduction.',
      );
    }
    final source = _sources[reciter.id];
    return BismillahResolution(
      source == null
          ? BismillahPolicyKind.unverified
          : BismillahPolicyKind.separateVerifiedRecording,
      source: source,
      evidence:
          source?.verification ??
          'No verified same-reciter Bismillah source available.',
    );
  }
}
