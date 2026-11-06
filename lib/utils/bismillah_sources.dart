import '../models/quran_audio.dart';
import 'bismillah_verified_sources.dart';

/// Only hash-bound, content-reviewed destinations enable an added introduction.
/// The evidence records automatic transcription, never human listening.
abstract final class BismillahSources {
  static final _policies = <String, Map<int, BismillahResolution>>{
    for (final reciter in verifiedOpeningData.entries)
      reciter.key: {
        for (final row in (reciter.value as Map<String, dynamic>).entries)
          int.parse(row.key): _policy(row.value as Map<String, dynamic>),
      },
  };

  static AudioRecordingSource _source(
    Map<String, dynamic> value, {
    List<AudioRecordingSource> alternatives = const [],
  }) => AudioRecordingSource(
    id: value['id'] as String,
    url: value['url'] as String,
    cacheFilename: value['cacheFilename'] as String,
    sha256: value['sha256'] as String,
    verification: value['verification'] as String,
    alternatives: List.unmodifiable(alternatives),
  );

  static BismillahResolution _policy(Map<String, dynamic> value) {
    final sources = (value['sources'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    return BismillahResolution(
      BismillahPolicyKind.values.byName(value['kind'] as String),
      openingSha256: value['openingSha256'] as String,
      evidence: value['evidence'] as String,
      source: sources.isEmpty
          ? null
          : _source(
              sources.first,
              alternatives: sources.skip(1).map((s) => _source(s)).toList(),
            ),
    );
  }

  static BismillahResolution resolve(Reciter reciter, int surah) {
    if (surah == 1 || surah == 9) {
      return const BismillahResolution(
        BismillahPolicyKind.notRequired,
        evidence:
            'Al-Fatihah already numbers Bismillah; At-Tawbah has no introduction.',
      );
    }
    return _policies[reciter.id]?[surah] ??
        const BismillahResolution(
          BismillahPolicyKind.unverified,
          evidence:
              'This destination has no conclusive content review. Directory presence '
              'or a successful MP3 download alone does not establish spoken content.',
        );
  }

  static List<int> unresolved(
    AudioPlaybackPlan plan,
    BismillahResolver resolver,
  ) => [
    for (final surah
        in plan
            .uniqueVerses()
            .where((v) => v.ayah == 1)
            .map((v) => v.surah)
            .toSet())
      if (resolver(plan.reciter, surah).kind == BismillahPolicyKind.unverified)
        surah,
  ];
}
