// Native decoder regression harness. See audio_repeat_smoke.md for invocation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/bismillah_sources.dart';

const _realAudio = bool.fromEnvironment('AUDIO_SMOKE_REAL');
const _audible = bool.fromEnvironment('AUDIO_SMOKE_AUDIBLE');
final _navigator = GlobalKey<NavigatorState>();
final _status = ValueNotifier<String>('Preparing native playback checks…');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      navigatorKey: _navigator,
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
    final fixture = File('${directory.path}/decoder_fixture.wav');
    await fixture.writeAsBytes(_tone(), flush: true);
    final player = AudioPlayer(maxSkipsOnError: 0);
    // Decode normally, quietly. Native EOF and item transitions must occur;
    // extrapolated position alone is not accepted as proof of a completed loop.
    await player.setVolume(_realAudio || _audible ? 1 : 0);
    final source = AudioSource.file(fixture.path);
    // This standalone diagnostic deliberately uses the test injection with a
    // real player, retaining the production background and native audio layers.
    // ignore: invalid_use_of_visible_for_testing_member
    final controller = QuranAudioController.forTesting(
      player: player,
      prepareSources: _realAudio ? null : (plan) async => [source],
      resolveIntroduction: _realAudio
          ? BismillahSources.resolve
          : _fixturePolicy,
    );
    await AudioService.init(
      builder: () => QuranAudioHandler(controller),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.quran.quran_double_page.audio',
        androidNotificationChannelName: 'Quran audio',
        androidNotificationOngoing: true,
      ),
    );
    try {
      for (final count in (_realAudio ? [1, 2] : [3, 5, 10])) {
        for (final ayahs in (_realAudio ? [2, 4] : [1, 2])) {
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

BismillahResolution _fixturePolicy(Reciter reciter, int surah) =>
    surah == 1 || surah == 9
    ? const BismillahResolution(
        BismillahPolicyKind.notRequired,
        evidence: 'Product rule',
      )
    : BismillahResolution(
        BismillahPolicyKind.separateVerifiedRecording,
        evidence: 'Generated diagnostic tone',
        source: AudioRecordingSource(
          id: 'tone',
          url: 'file:///diagnostic-tone.wav',
          cacheFilename: 'diagnostic-tone.wav',
          verification: 'Generated tone; no reciter-content claim',
        ),
      );

Future<Map<String, Object?>> _check(
  QuranAudioController controller,
  AudioPlayer player,
  AudioPlaybackPlan plan, {
  int? stopAfter,
}) async {
  _status.value =
      'Checking ${plan.rangeLabel}, ${plan.repeatLabel}, ${plan.repeatMode.name}';
  final watch = Stopwatch()..start();
  final transitions = <Map<String, Object?>>[];
  final progressed = <String>{};
  var nativeEnds = 0, maxQueue = 0, maxSources = 0;
  String? lastOccurrence;
  int? previousStart, previousDuration;
  void capture() {
    if (!player.playing || player.processingState != ProcessingState.ready) {
      return;
    }
    final tag = player.sequenceState.currentSource?.tag;
    if (tag is! QuranAudioOccurrence) return;
    maxQueue = math.max(maxQueue, player.sequence.length);
    // ignore: invalid_use_of_visible_for_testing_member
    maxSources = math.max(maxSources, player.retainedAudioSourceCount);
    if (lastOccurrence == tag.occurrenceId) {
      previousDuration ??= player.duration?.inMilliseconds;
      if (!tag.item.isIntroduction && player.position.inMilliseconds >= 100) {
        progressed.add(tag.occurrenceId);
      }
      return;
    }
    final now = watch.elapsedMilliseconds;
    transitions.add({
      'occurrence': tag.occurrenceId,
      'recording': tag.recordingId,
      'item': tag.item.key,
      'verseRepeat': tag.verseRepetition,
      'rangeCycle': tag.rangeCycle,
      'atMs': now,
      'previousDurationMs': previousDuration,
      'boundaryEventExcessMs': previousStart == null || previousDuration == null
          ? null
          : now - previousStart! - previousDuration!,
      'positionMs': player.position.inMilliseconds,
    });
    lastOccurrence = tag.occurrenceId;
    previousStart = now;
    previousDuration = player.duration?.inMilliseconds;
  }

  final sequenceSub = player.sequenceStateStream.listen((_) => capture());
  final completionSub = player.processingStateStream.listen((state) {
    if (state == ProcessingState.completed) nativeEnds++;
  });
  final timer = Timer.periodic(
    const Duration(milliseconds: 20),
    (_) => capture(),
  );
  try {
    await controller.playPlan(plan);
    if (!controller.hasActivePlayback) {
      throw StateError('Playback was cancelled before starting');
    }
    while (controller.hasActivePlayback) {
      capture();
      if (stopAfter != null && transitions.length >= stopAfter) {
        await controller.stop();
        break;
      }
      if (controller.error != null) throw StateError(controller.error!);
      if (watch.elapsed > Duration(minutes: _realAudio ? 10 : 2)) {
        throw StateError('Native playback stalled');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final intros = plan
        .uniqueVerses()
        .where(
          (v) =>
              v.ayah == 1 &&
              controller.resolveIntroduction(plan.reciter, v.surah).kind ==
                  BismillahPolicyKind.separateVerifiedRecording,
        )
        .length;
    final expected =
        plan.uniqueAyahCount * plan.visibleRepeatCount +
        intros *
            (plan.repeatMode == AudioRepeatMode.range
                ? plan.visibleRepeatCount
                : 1);
    if (stopAfter == null &&
        (transitions.length != expected ||
            progressed.length <
                plan.uniqueAyahCount * plan.visibleRepeatCount)) {
      throw StateError(
        'Expected $expected occurrences; observed ${transitions.length}, ${progressed.length} advancing ayahs',
      );
    }
    if (maxQueue > 6 || maxSources > 7) {
      throw StateError('Unbounded native queue/source registrations');
    }
    return {
      'repeatCount': plan.repeatCount,
      'repeatMode': plan.repeatMode.name,
      'sourceMode': plan.sourceMode.name,
      'realRecitations': _realAudio,
      'nativeEnds': nativeEnds,
      'queueLoads': controller.queueReloadCount,
      'maxQueue': maxQueue,
      'maxRegisteredSourcesIncludingRoot': maxSources,
      'advancingAyahs': progressed.length,
      'elapsedMs': watch.elapsedMilliseconds,
      'transitions': transitions,
      'intrinsicFixtureHeadSilenceMs': _realAudio ? null : 40,
      'intrinsicFixtureTailSilenceMs': _realAudio ? null : 60,
      'measurement':
          'Native index-event intervals, not an audio-output gap measurement. '
          'Recording duration includes its existing silence; no trimming or crossfade.',
    };
  } finally {
    timer.cancel();
    await sequenceSub.cancel();
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
      i < rate * .04 || i >= samples - rate * .06
          ? 0
          : (math.sin(2 * math.pi * 440 * i / rate) * 8000).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
