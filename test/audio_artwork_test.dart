import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/audio_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled app icon becomes decodable local media artwork', () async {
    final directory = await Directory.systemTemp.createTemp('quran_artwork_');
    addTearDown(() => directory.delete(recursive: true));
    final uri = await prepareAudioArtwork(directory);
    expect(uri.scheme, 'file');
    final bytes = await File.fromUri(uri).readAsBytes();
    final bundled = await rootBundle.load(audioArtworkAsset);
    expect(
      bytes,
      bundled.buffer.asUint8List(bundled.offsetInBytes, bundled.lengthInBytes),
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1024);
    expect(frame.image.height, 1024);
    frame.image.dispose();
    codec.dispose();
  });

  test(
    'old artwork is bypassed and an incomplete PNG cache is repaired',
    () async {
      final directory = await Directory.systemTemp.createTemp('quran_artwork_');
      addTearDown(() => directory.delete(recursive: true));
      await File('${directory.path}/audio_artwork.jpeg').writeAsBytes([0]);
      final first = await prepareAudioArtwork(directory);
      await File.fromUri(first).writeAsBytes([1, 2]);
      final repaired = await prepareAudioArtwork(directory);
      expect(repaired, first);
      expect(File.fromUri(repaired).path, endsWith('audio_artwork_v2.png'));
      final bundled = await rootBundle.load(audioArtworkAsset);
      expect(await File.fromUri(repaired).length(), bundled.lengthInBytes);
      // Reusing a complete cache must not rewrite the file on every play.
      final modified = await File.fromUri(repaired).lastModified();
      await prepareAudioArtwork(directory);
      expect(await File.fromUri(repaired).lastModified(), modified);
    },
  );
}
