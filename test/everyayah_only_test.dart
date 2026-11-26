import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/logic/audio_repository.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/bismillah_sources.dart';
import 'package:mushaf_two_page/utils/retired_audio_cache.dart';

void main() {
  test('all 22 production reciters use only EveryAyah recordings', () {
    final repository = AudioRepository();
    expect(quranReciters, hasLength(22));
    for (final reciter in quranReciters) {
      final source = repository.sourceFor(
        reciter,
        const QuranAudioItem(surah: 67, ayah: 1),
      );
      expect(Uri.parse(source.url).host, 'everyayah.com');
      final intro = BismillahSources.resolve(reciter, 67).source;
      if (intro != null) {
        for (final recording in [intro, ...intro.alternatives]) {
          expect(Uri.parse(recording.url).host, 'everyayah.com');
        }
      }
    }
  });
  test('retired provider, flag, modal indicator and timing API are absent', () {
    final forbidden = [
      'Mp3Quran',
      'EXPERIMENTAL_MP3QURAN',
      'api-staging.mp3quran.net',
      'DevelopmentAudioSourceIndicator',
      'QuranAudioProvider',
    ];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final text in forbidden) {
        expect(source, isNot(contains(text)), reason: file.path);
      }
    }
  });
  test(
    'startup cleanup deletes only the retired namespace, including symlinks',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'audio-cache-migration-',
      );
      addTearDown(() => root.delete(recursive: true));
      final numbered = File('${root.path}/audio/alafasy/067001.mp3');
      await numbered.parent.create(recursive: true);
      await numbered.writeAsString('keep EveryAyah bytes');
      final retired = Directory('${root.path}/mp3quran');
      await retired.create();
      await File('${retired.path}/067.mp3').writeAsString('retired');
      await Link('${retired.path}/outside').create(numbered.parent.path);
      await removeRetiredAudioCache(documents: () async => root);
      expect(await retired.exists(), isFalse);
      expect(await numbered.readAsString(), 'keep EveryAyah bytes');
      await Link(retired.path).create(numbered.parent.path);
      await removeRetiredAudioCache(documents: () async => root);
      expect(await Link(retired.path).exists(), isFalse);
      expect(await numbered.readAsString(), 'keep EveryAyah bytes');
      await removeRetiredAudioCache(documents: () async => root); // idempotent
    },
  );
}
