import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/models/everyayah_pcm_proof.dart';

const directory = String.fromEnvironment('EVERYAYAH_PCM_PROOF_DIRECTORY');
void main() {
  test(
    'actual generated Yasser artifact passes the app WAV/hash/timeline validator',
    () async {
      final expected = jsonDecode(
        File('docs/everyayah-pcm-yasser-proof.json').readAsStringSync(),
      );
      final source = await EveryAyahPcmProof.load(Directory(directory));
      expect(source.sha256, expected['waveSha256']);
      expect(source.frames, expected['frames']);
      expect(source.rows, hasLength(11));
      for (final row in source.rows) {
        expect(source.at(source.time(row.startFrame)), same(row));
      }
    },
    skip: directory.isEmpty,
  );
}
