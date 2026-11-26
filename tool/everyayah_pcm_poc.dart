// Stage-A development entry point. Production main never registers this proof.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mushaf_two_page/main.dart' as app;
import 'package:mushaf_two_page/models/everyayah_pcm_proof.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) throw StateError('PCM proof is development only');
  const override = String.fromEnvironment('EVERYAYAH_PCM_PROOF_DIRECTORY');
  final path = override.isNotEmpty
      ? override
      : '${(await getApplicationSupportDirectory()).path}/pcm_proof';
  final proof = await EveryAyahPcmProof.load(Directory(path));
  QuranAudioController.instance.registerPcmProofForDevelopment(proof);
  app.main();
}
