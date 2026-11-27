import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/recording_stereo_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('quran/pcm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'concurrent occurrences share analysis and a replaced file is measured again',
    () async {
      final dir = await Directory.systemTemp.createTemp('recording-polarity');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/a.mp3');
      await file.writeAsBytes([1]);
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'needsStereoCorrection');
        expect(call.arguments['path'], file.path);
        return ++calls == 1;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final probe = RecordingStereoProbe();
      expect(
        await Future.wait([probe.inspect(file.path), probe.inspect(file.path)]),
        [true, true],
      );
      expect(await probe.inspect(file.path), isTrue);
      await file.writeAsBytes([2, 3]);
      expect(await probe.inspect(file.path), isFalse);
      expect(calls, 2);
    },
  );
}
