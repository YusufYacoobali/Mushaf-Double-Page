import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// Exercises the real just_audio Dart playlist/registration code. Only the OS
/// channel is replaced; a FakePlayer cannot detect the upstream retention bug.
class _Platform extends JustAudioPlatform {
  late _Native native;
  @override
  Future<AudioPlayerPlatform> init(InitRequest r) async =>
      native = _Native(r.id);
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest r,
  ) async => DisposeAllPlayersResponse();
  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest r) async =>
      DisposePlayerResponse();
}

class _Native extends AudioPlayerPlatform {
  _Native(super.id);
  final events = StreamController<PlaybackEventMessage>.broadcast();
  int index = 0;
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => events.stream;
  void emit() => events.add(
    PlaybackEventMessage(
      processingState: ProcessingStateMessage.ready,
      updateTime: DateTime.now(),
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      duration: const Duration(seconds: 1),
      icyMetadata: null,
      currentIndex: index,
      androidAudioSessionId: null,
    ),
  );
  @override
  Future<LoadResponse> load(LoadRequest r) async {
    index = r.initialIndex ?? 0;
    emit();
    return LoadResponse(duration: const Duration(seconds: 1));
  }

  @override
  Future<ConcatenatingInsertAllResponse> concatenatingInsertAll(
    ConcatenatingInsertAllRequest r,
  ) async => ConcatenatingInsertAllResponse();
  @override
  Future<ConcatenatingRemoveRangeResponse> concatenatingRemoveRange(
    ConcatenatingRemoveRangeRequest r,
  ) async {
    if (index >= r.endIndex) index -= r.endIndex - r.startIndex;
    emit();
    return ConcatenatingRemoveRangeResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest r) async =>
      SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest r) async =>
      SetSpeedResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest r) async =>
      SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest r,
  ) async => SetShuffleModeResponse();
  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
    SetShuffleOrderRequest r,
  ) async => SetShuffleOrderResponse();
  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
  setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest r,
  ) async => SetAutomaticallyWaitsToMinimizeStallingResponse();
  @override
  Future<SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse>
  setCanUseNetworkResourcesForLiveStreamingWhilePaused(
    SetCanUseNetworkResourcesForLiveStreamingWhilePausedRequest r,
  ) async => SetCanUseNetworkResourcesForLiveStreamingWhilePausedResponse();
  @override
  Future<SetAllowsExternalPlaybackResponse> setAllowsExternalPlayback(
    SetAllowsExternalPlaybackRequest r,
  ) async => SetAllowsExternalPlaybackResponse();
  @override
  Future<SeekResponse> seek(SeekRequest r) async {
    index = r.index ?? index;
    emit();
    return SeekResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest r) async => DisposeResponse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real player releases retired definitions and preserves identity while removing prefix',
    () async {
      final original = JustAudioPlatform.instance;
      final platform = _Platform();
      JustAudioPlatform.instance = platform;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.ryanheise.audio_session'),
            (_) async => null,
          );
      final player = AudioPlayer(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
      );
      final observed = <Object?>[];
      final subscription = player.sequenceStateStream.listen(
        (s) => observed.add(s.currentSource?.tag),
      );
      AudioSource source(int i) =>
          AudioSource.uri(Uri.parse('https://example.test/$i.mp3'), tag: i);
      await player.setAudioSources([
        source(0),
        source(1),
        source(2),
        source(3),
      ], initialIndex: 2);
      await Future<void>.delayed(Duration.zero);
      observed.clear();
      await player.removeAudioSourceRange(0, 1);
      await Future<void>.delayed(Duration.zero);
      expect(player.sequenceState.currentSource!.tag, 2);
      expect(observed.where((s) => s != 2), isEmpty);
      for (var i = 4; i < 1004; i++) {
        await player.addAudioSource(source(i));
        await player.removeAudioSourceRange(0, 1);
        // ignore: invalid_use_of_visible_for_testing_member
        expect(player.retainedAudioSourceCount, lessThanOrEqualTo(5));
      }
      await subscription.cancel();
      await player.dispose();
      JustAudioPlatform.instance = original;
    },
  );
}
