import 'dart:io';

import 'package:flutter/services.dart';

const audioArtworkAsset = 'assets/icon/audio_artwork.png';

/// Both native media-control implementations need a real local artwork file.
Future<Uri> prepareAudioArtwork(Directory directory) async {
  final data = await rootBundle.load(audioArtworkAsset);
  // A new name prevents old/malformed JPEG artwork being reused after updating.
  final file = File('${directory.path}/audio_artwork_v2.png');
  if (!await file.exists() || await file.length() != data.lengthInBytes) {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
  return file.uri;
}
