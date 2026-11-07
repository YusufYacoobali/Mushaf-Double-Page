import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'audio_test_fixtures.dart';
import 'everyayah_pcm_timeline_test.dart' show syntheticProof;

void main() {
  test('release refuses explicit PCM proof registration', () {
    final c = QuranAudioController.forTesting(
      player: FakePlayer(),
      repository: ControlledRepository(),
    );
    expect(
      () => c.registerPcmProofForDevelopment(syntheticProof()),
      throwsStateError,
    );
    c.dispose();
  }, skip: !kReleaseMode);
}
