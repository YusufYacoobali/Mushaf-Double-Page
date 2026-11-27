import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import '../models/quran_audio.dart';
import 'quran_audio_controller.dart';

/// A command/metadata bridge, not a second playback state machine. Lock screen,
/// Bluetooth and app controls all operate the same logical cursor.
class QuranAudioHandler extends BaseAudioHandler with SeekHandler {
  QuranAudioHandler(this.controller) {
    controller.addListener(_publish);
    _publish();
  }
  final QuranAudioController controller;
  final _sessionSubscriptions = <StreamSubscription<dynamic>>[];

  void bindSessionEvents({
    required Stream<void> becomingNoisy,
    required Stream<AudioInterruptionEvent> interruptions,
  }) {
    for (final subscription in _sessionSubscriptions) {
      unawaited(subscription.cancel());
    }
    _sessionSubscriptions
      ..clear()
      ..add(becomingNoisy.listen((_) => unawaited(pause())))
      ..add(
        interruptions.listen((event) {
          // Interruption end is not permission to resume. Only a Play command is.
          if (event.begin) unawaited(pause());
        }),
      );
  }

  Future<void> dispose() async {
    controller.removeListener(_publish);
    await Future.wait(_sessionSubscriptions.map((s) => s.cancel()));
    _sessionSubscriptions.clear();
  }

  // Play the original stereo master as ordinary media. Keep the reader's
  // interruption and ducking behaviour independent of the content type.
  static const playbackSession = AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playback,
    avAudioSessionMode: AVAudioSessionMode.defaultMode,
    androidAudioAttributes: AndroidAudioAttributes(
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    androidWillPauseWhenDucked: true,
  );

  static Future<QuranAudioHandler> initialize() async {
    final handler = await AudioService.init(
      builder: () => QuranAudioHandler(QuranAudioController.instance),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.quran.quran_double_page.audio',
        androidNotificationChannelName: 'Quran audio',
        androidNotificationChannelDescription: 'Quran recitation playback',
        androidNotificationOngoing: true,
        artDownscaleWidth: 512,
        artDownscaleHeight: 512,
      ),
    );
    final session = await AudioSession.instance;
    await session.configure(playbackSession);
    handler.bindSessionEvents(
      becomingNoisy: session.becomingNoisyEventStream,
      interruptions: session.interruptionEventStream,
    );
    await handler.controller.prepareArtwork();
    return handler;
  }

  void _publish() {
    final c = controller;
    if (mediaItem.value != c.currentMediaItem) {
      mediaItem.add(c.currentMediaItem);
    }
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          c.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.seek,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.stop,
        },
        processingState: switch (c.phase) {
          QuranPlaybackPhase.idle => AudioProcessingState.idle,
          QuranPlaybackPhase.preparing => AudioProcessingState.loading,
          QuranPlaybackPhase.buffering ||
          QuranPlaybackPhase.recovering => AudioProcessingState.buffering,
          QuranPlaybackPhase.completed => AudioProcessingState.completed,
          QuranPlaybackPhase.failed => AudioProcessingState.error,
          _ => AudioProcessingState.ready,
        },
        playing: c.playing,
        updatePosition: c.playbackPosition,
        bufferedPosition: c.bufferedPlaybackPosition,
        speed: 1,
        errorCode: c.failure == null ? null : 1,
        errorMessage: c.error,
      ),
    );
  }

  @override
  Future<void> play() => controller.play();
  @override
  Future<void> pause() => controller.pause();
  @override
  Future<void> stop() => controller.stop();
  @override
  Future<void> skipToNext() => controller.seekNext();
  @override
  Future<void> skipToPrevious() => controller.seekPrevious();
  @override
  Future<void> seek(Duration position) => controller.seek(position);
  @override
  Future<void> onTaskRemoved() => stop();
}
