import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/audio_modal.dart';
import 'package:mushaf_two_page/logic/mp3quran_repository.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';

class _UnusedContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Exercise release constants without mounting debug-engine widgets in product
// mode. Run with --dart-define=dart.vm.product=true and the pilot opt-in flag.
void main() {
  test(
    'development opt-in exposes the audited manifest',
    () {
      expect(Mp3QuranPilot.enabled, isTrue);
      expect(Mp3QuranPilot.verifiedManifest, isNotNull);
      expect(DevelopmentAudioSourceIndicator.visible, isTrue);
    },
    skip:
        kReleaseMode ||
        !const bool.fromEnvironment('EXPERIMENTAL_MP3QURAN_AL_MULK'),
  );
  test(
    'release removes provider indicator and blocks pilot despite opt-in',
    () {
      expect(kReleaseMode, isTrue);
      expect(DevelopmentAudioSourceIndicator.visible, isFalse);
      for (final provider in QuranAudioProvider.values) {
        final widget = DevelopmentAudioSourceIndicator(provider: provider);
        final result = widget.build(_UnusedContext());
        expect(result, isA<SizedBox>());
        expect((result as SizedBox).width, 0);
        expect(result.height, 0);
      }
      expect(Mp3QuranPilot.enabled, isFalse);
      expect(Mp3QuranPilot.verifiedManifest, isNull);
    },
    skip: !kReleaseMode,
  );
}
