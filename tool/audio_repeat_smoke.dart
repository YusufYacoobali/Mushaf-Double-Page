// Native decoder regression harness. See audio_repeat_smoke.md for invocation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';

final _status = ValueNotifier<String>('Preparing native playback checks…');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: _status,
            builder: (_, status, _) =>
                Text(status, textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );
  final directory = await getApplicationSupportDirectory();
  final report = File('${directory.path}/audio_repeat_report.json');
  final results = <Map<String, Object?>>[];
  Future<void> save(String state, [Object? error]) async {
    await report.writeAsString(
      jsonEncode({
        'state': state,
        'platform': Platform.operatingSystem,
        'results': results,
        if (error != null) 'error': error.toString(),
      }),
      flush: true,
    );
  }

  await save('running');
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'audio_repeat_smoke',
      androidNotificationChannelName: 'Audio repeat diagnostic',
      androidNotificationOngoing: true,
    );
    final fixture = File('${directory.path}/decoder_fixture.wav');
    await fixture.writeAsBytes(_tone(), flush: true);
    final player = AudioPlayer(maxSkipsOnError: 0);
    // Decode normally, quietly. Native EOF and item transitions must occur;
    // extrapolated position alone is not accepted as proof of a completed loop.
    await player.setVolume(0);
    var loads = 0;
    // This standalone diagnostic deliberately uses the test injection with a
    // real player, retaining the production background and native audio layers.
    // ignore: invalid_use_of_visible_for_testing_member
    final controller = QuranAudioController.forTesting(
      player: player,
      prepareSources: (plan) async {
        loads++;
        final verses = plan.repeatMode == AudioRepeatMode.range
            ? plan.uniqueVerses()
            : plan.playbackVerses();
        return [
          for (var i = 0; i < verses.length; i++)
            AudioSource.file(
              fixture.path,
              tag: MediaItem(
                id: '$loads:$i',
                title: 'Decoder check ${verses[i].surah}:${verses[i].ayah}',
              ),
            ),
        ];
      },
    );
    try {
      for (final count in [3, 5, 10]) {
        for (final ayahs in [1, 2]) {
          results.add(await _check(controller, player, _plan(count, ayahs)));
          await save('running');
        }
      }
      results.add(
        await _check(
          controller,
          player,
          _plan(5, 2, repeatMode: AudioRepeatMode.ayah),
        ),
      );
      await save('running');
      results.add(await _check(controller, player, _plan(3, 1, queue: true)));
      await save('running');
      results.add(
        await _check(controller, player, _plan(null, 1), stopAfter: 12),
      );
      await save('passed');
      _status.value = '${results.length} native playback checks passed';
    } finally {
      await controller.stop();
      await player.dispose();
      controller.dispose();
    }
  } catch (error, stack) {
    await save('failed', '$error\n$stack');
    _status.value = 'Native playback check failed: $error';
  }
}

AudioPlaybackPlan _plan(
  int? count,
  int ayahs, {
  AudioRepeatMode repeatMode = AudioRepeatMode.range,
  bool queue = false,
}) => AudioPlaybackPlan(
  reciter: quranReciters.first,
  surah: 112,
  fromAyah: 1,
  toAyah: ayahs,
  repeatCount: count,
  repeatMode: repeatMode,
  sourceMode: queue ? AudioSourceMode.playlist : AudioSourceMode.range,
  surahQueue: queue ? [112, 114] : const [],
);

Future<Map<String, Object?>> _check(
  QuranAudioController controller,
  AudioPlayer player,
  AudioPlaybackPlan plan, {
  int? stopAfter,
}) async {
  _status.value =
      'Checking ${plan.rangeLabel}, ${plan.repeatLabel}, ${plan.repeatMode.name}';
  var completions = 0;
  final progressed = <String>{};
  final completionSub = player.processingStateStream.listen((state) {
    if (state == ProcessingState.completed) completions++;
  });
  final timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
    if (controller.playing &&
        player.processingState == ProcessingState.ready &&
        player.position.inMilliseconds >= 100 &&
        controller.currentAyah != null) {
      progressed.add(
        '${controller.currentRepeat}:${controller.currentSurah}:${controller.currentAyah}',
      );
    }
  });
  final watch = Stopwatch()..start();
  try {
    await controller.playPlan(plan);
    while (controller.hasActivePlayback) {
      if (stopAfter != null && completions >= stopAfter) {
        await controller.stop();
        break;
      }
      if (watch.elapsed > const Duration(seconds: 60)) {
        throw StateError(
          'Playback stalled: cycle=${controller.currentRepeat}, '
          'nativeEOF=$completions, ayah=${controller.currentAyah}, '
          'state=${player.processingState}, playing=${player.playing}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Allow stream deliveries from the final native EOF to settle.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (controller.error != null) throw StateError(controller.error!);
    final expectedCompletions =
        stopAfter ??
        (plan.repeatMode == AudioRepeatMode.range
            ? plan.visibleRepeatCount
            : 1);
    final expectedItems =
        (stopAfter ?? plan.visibleRepeatCount) * plan.uniqueAyahCount;
    if (completions != expectedCompletions ||
        progressed.length < expectedItems) {
      throw StateError(
        'Expected $expectedCompletions native EOFs and $expectedItems '
        'advancing ayahs; got $completions EOFs and ${progressed.length} ayahs.',
      );
    }
    return {
      'repeatCount': plan.repeatCount,
      'repeatMode': plan.repeatMode.name,
      'sourceMode': plan.sourceMode.name,
      'ayahsPerCycle': plan.uniqueAyahCount,
      'nativeCompletions': completions,
      'advancingAyahs': progressed.length,
      'elapsedMs': watch.elapsedMilliseconds,
    };
  } finally {
    timer.cancel();
    await completionSub.cancel();
    await controller.stop();
  }
}

Uint8List _tone() {
  const rate = 22050, samples = rate ~/ 2;
  final data = ByteData(44 + samples * 2);
  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(
      44 + i * 2,
      (math.sin(2 * math.pi * 440 * i / rate) * 8000).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
