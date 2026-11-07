// Synthetic native output capture target. Never evidence of reciter timing.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/logic/audio_playback_backend.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';

const _control = bool.fromEnvironment('AUDIO_TRANSITION_CONTROL');
const _directory = String.fromEnvironment('AUDIO_TRANSITION_DIRECTORY');
// Diagnostic baseline selector only. Production continuous playback is default.
const _legacy = bool.fromEnvironment('AUDIO_TRANSITION_LEGACY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier('Loading synthetic transition probe…');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: status,
            builder: (_, text, _) => Text(text),
          ),
        ),
      ),
    ),
  );
  QuranAudioController? controller;
  QuranAudioHandler? handler;
  try {
    final root = _directory.isNotEmpty
        ? _directory
        : '${(await getApplicationSupportDirectory()).path}/transition_probe';
    final manifest =
        jsonDecode(await File('$root/manifest.json').readAsString())
            as Map<String, dynamic>;
    final parts = manifest['parts'] as List;
    final controlFile = File('$root/${manifest['unsplitControl']}');
    if ((await sha256.bind(controlFile.openRead()).first).toString() !=
        manifest['unsplitSha256']) {
      throw StateError('Synthetic control hash mismatch');
    }
    for (final part in parts) {
      final file = File('$root/${part['file']}');
      if ((await sha256.bind(file.openRead()).first).toString() !=
          part['sha256']) {
        throw StateError('Synthetic probe hash mismatch');
      }
    }
    final player = AudioPlayer(maxSkipsOnError: 0, handleInterruptions: false);
    await player.setVolume(1);
    // ignore: invalid_use_of_visible_for_testing_member
    final c = controller = QuranAudioController.forTesting(
      player: player,
      continuousBackend: !_control && !_legacy && ContinuousPcmBackend.supported
          ? ContinuousPcmBackend()
          : null,
      prepareSources: (_) async => _control
          ? [AudioSource.file('$root/${manifest['unsplitControl']}')]
          : [
              for (final part in parts)
                AudioSource.file('$root/${part['file']}'),
            ],
      resolveIntroduction: (_, _) => const BismillahResolution(
        BismillahPolicyKind.notRequired,
        evidence: 'Synthetic probe; not recitation',
      ),
    );
    handler = await AudioService.init(
      builder: () => QuranAudioHandler(c),
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.quran.quran_double_page.transition_probe',
        androidNotificationChannelName: 'Synthetic transition probe',
      ),
    );
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    handler.bindSessionEvents(
      becomingNoisy: session.becomingNoisyEventStream,
      interruptions: session.interruptionEventStream,
    );
    final events = <Map<String, Object?>>[];
    final clock = Stopwatch()..start();
    final done = Completer<void>();
    int? firstRenderedUs;
    var previous = '';
    c.addListener(() {
      if (c.audible) firstRenderedUs ??= clock.elapsedMicroseconds;
      final key = c.currentOccurrence?.occurrenceId ?? '';
      if (key != previous) {
        previous = key;
        events.add({
          'eventUs': clock.elapsedMicroseconds,
          'ayah': c.currentAyah,
          'cycle': c.currentRepeat,
          'phase': c.phase.name,
        });
      }
      if (!done.isCompleted &&
          (c.error != null ||
              c.phase == QuranPlaybackPhase.completed ||
              (!_control && (c.currentRepeat ?? 1) > 1))) {
        done.complete();
      }
    });
    status.value = _control
        ? 'Playing unsplit control'
        : 'Playing two split MP3s';
    // Planning three cycles forces ordinary bounded lookahead edits while the
    // first cycle plays. Stop as cycle two begins so the captured signal has
    // only the first two complete markers, with no ambiguous repeated anchors.
    await c.playPlan(
      AudioPlaybackPlan(
        reciter: quranReciters.first,
        surah: 112,
        fromAyah: 1,
        toAyah: _control ? 1 : 2,
        repeatCount: _control ? 1 : 3,
        repeatMode: AudioRepeatMode.range,
        sourceMode: AudioSourceMode.range,
      ),
    );
    await done.future.timeout(const Duration(seconds: 30));
    final error = c.error;
    final reloads = c.queueReloadCount;
    final backend = c.activeBackend;
    final fallback = c.continuousFallbackReason;
    await c.stop();
    await File(
      '$root/${_control ? 'control' : 'split'}-events.json',
    ).writeAsString(
      jsonEncode({
        'platform': Platform.operatingSystem,
        'control': _control,
        'queueLoads': reloads,
        'backend': backend,
        'fallbackReason': fallback,
        'firstRenderedEventUs': firstRenderedUs,
        'events': events,
        'nativeOutputGapMs': null,
        'note':
            'Events are not audible output measurements. Analyze a captured WAV separately.',
        if (error != null) 'error': error,
      }),
    );
    if (error != null) throw StateError(error);
    if (!_control && !_legacy && backend != 'continuous-pcm') {
      throw StateError('Continuous probe fell back: $fallback');
    }
    status.value =
        'Probe complete. Analyze captured output; event timing is not a gap measurement.';
  } catch (error) {
    status.value = 'Probe failed: $error';
  } finally {
    await controller?.stop();
    await handler?.dispose();
    controller?.dispose();
  }
}
