import 'dart:async';

import 'package:dio/dio.dart';

import '../models/quran_audio.dart';
import 'audio_repository.dart';

class AudioDownloadState {
  const AudioDownloadState({
    required this.active,
    required this.completed,
    required this.total,
    required this.message,
    this.fraction,
  });
  const AudioDownloadState.idle()
    : active = false,
      completed = 0,
      total = 0,
      message = '',
      fraction = null;
  final bool active;
  final int completed, total;
  final String message;
  final double? fraction;
  double? get progress => fraction ?? (total == 0 ? null : completed / total);
}

/// Owns a single replaceable, low-priority offline selection. Playback and
/// offline jobs share the repository's cache and request scheduler.
class OfflineAudioDownloads {
  OfflineAudioDownloads({
    required this.repository,
    required this.retryDelay,
    required this.resolveIntroduction,
    required this.resolveItem,
    required this.isOmittedIntroduction,
    required this.onChanged,
  });
  final AudioRecordingRepository repository;
  final Duration retryDelay;
  final BismillahResolver resolveIntroduction;
  final QuranAudioItem Function(Reciter, QuranAudioItem) resolveItem;
  final bool Function(String) isOmittedIntroduction;
  final void Function() onChanged;
  AudioDownloadState _state = const AudioDownloadState.idle();
  AudioDownloadState get state => _state;
  CancelToken? _token;
  bool _needsRefresh = false;

  void interruptForRepair() {
    if (_token == null || _token!.isCancelled) return;
    cancel();
    _needsRefresh = true;
  }

  void resumeAfterRepair(AudioPlaybackPlan selection) {
    if (!_needsRefresh) return;
    _needsRefresh = false;
    unawaited(save(selection));
  }

  Future<void> save(AudioPlaybackPlan selection) async {
    _token?.cancel('New offline selection');
    final token = _token = CancelToken();
    final items = <String, QuranAudioItem>{};
    var unavailable = 0;
    for (final verse in selection.uniqueVerses()) {
      if (verse.ayah == 1) {
        final resolution = resolveIntroduction(selection.reciter, verse.surah);
        if (resolution.kind == BismillahPolicyKind.unverified) unavailable++;
        if (resolution.kind == BismillahPolicyKind.separateVerifiedRecording &&
            resolution.source != null) {
          items[resolution.source!.id] = QuranAudioItem(
            surah: verse.surah,
            source: resolution.source,
          );
        }
      }
      final item = resolveItem(
        selection.reciter,
        QuranAudioItem(surah: verse.surah, ayah: verse.ayah),
      );
      // A canonical 001001 can also be the numbered Fatihah 1:1 recording.
      items.putIfAbsent(item.recordingId, () => item);
    }
    var done = 0;
    var failed = 0;
    try {
      for (final item in items.values) {
        if (token.isCancelled) throw token.cancelError!;
        if (item.isIntroduction && isOmittedIntroduction(item.recordingId)) {
          failed++;
          continue;
        }
        _state = AudioDownloadState(
          active: true,
          completed: done,
          total: items.length,
          message: 'Saving audio offline · $done/${items.length}',
        );
        onChanged();
        var saved = false;
        for (var attempt = 0; attempt < 4; attempt++) {
          try {
            await repository.recording(
              selection.reciter,
              item,
              token,
              urgent: false,
            );
            saved = true;
            break;
          } catch (error) {
            if (token.isCancelled) throw token.cancelError!;
            if (attempt == 3 || (error is AudioFailure && !error.recoverable)) {
              break;
            }
            await Future.any([
              Future<void>.delayed(retryDelay * (1 << attempt)),
              token.whenCancel.then<void>((_) {}),
            ]);
            if (token.isCancelled) throw token.cancelError!;
          }
        }
        if (saved) {
          done++;
        } else {
          failed++;
        }
      }
      if (!token.isCancelled && _token == token) {
        _state = AudioDownloadState(
          active: false,
          completed: done,
          total: items.length,
          message: unavailable == 0 && failed == 0
              ? 'Selection available offline'
              : 'Offline audio incomplete · $failed recording(s) unavailable'
                    '${unavailable == 0 ? "" : "; Bismillah unavailable for $unavailable opening(s)"}',
        );
      }
    } catch (error) {
      if (!token.isCancelled && _token == token) {
        _state = AudioDownloadState(
          active: false,
          completed: done,
          total: items.length,
          message: 'Offline saving stopped: $error',
        );
      }
    }
    onChanged();
  }

  void cancel() {
    _token?.cancel();
    _token = null;
    _needsRefresh = false;
    _state = const AudioDownloadState.idle();
    onChanged();
  }

  void dispose() => _token?.cancel();
}
