import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/models/everyayah_pcm_proof.dart';

EveryAyahPcmProof syntheticProof() => EveryAyahPcmProof(
  path: '/synthetic/continuous.wav',
  sha256: '',
  sampleRate: 44100,
  rows: [
    for (var i = 0; i <= 10; i++)
      PcmProofOccurrence(
        i == 0 ? null : i,
        i * 44100,
        (i + 1) * 44100,
        'synthetic-$i',
      ),
  ],
);
void main() {
  test(
    'sample boundaries are exact, half-open and include distinct Bismillah',
    () {
      final p = syntheticProof();
      expect(p.at(Duration.zero)!.ayah, isNull);
      for (var a = 1; a <= 10; a++) {
        expect(p.at(p.time(a * 44100))!.ayah, a);
        expect(
          p.at(p.time(a * 44100) - const Duration(microseconds: 1))!.ayah,
          a == 1 ? null : a - 1,
        );
      }
      expect(p.at(p.time(p.frames)), isNull);
      expect(p.rows.map((r) => r.id).toSet(), hasLength(11));
    },
  );
  test('noncontiguous or duplicated occurrences are rejected', () {
    final rows = syntheticProof().rows.toList();
    rows[2] = PcmProofOccurrence(2, 88201, 132300, 'synthetic-2');
    expect(
      () => EveryAyahPcmProof(
        path: '',
        sha256: '',
        sampleRate: 44100,
        rows: rows,
      ),
      throwsArgumentError,
    );
  });
}
