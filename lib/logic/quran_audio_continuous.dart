part of 'quran_audio_controller.dart';

/// The experimental path shares the controller's player, intent, session guards,
/// background handler and tracker. It never fills the EveryAyah native queue.
extension _ContinuousPlayback on QuranAudioController {
  Future<void> _prepareContinuous(int generation, int revision) async {
    _continuous = true;
    _continuousLoaded = false;
    _installing = true;
    _current = _entry(QuranPlaybackCursor(_plan!));
    try {
      final path = await _continuousRepository.recording(
        _token,
        onProgress: (value) {
          if (!_valid(generation, revision)) return;
          _download = AudioDownloadState(
            active: true,
            completed: 0,
            total: 1,
            message: 'Downloading Al-Mulk',
            fraction: value,
          );
          _publish();
        },
      );
      if (!_valid(generation, revision)) return;
      await _native(() async {
        if (!_valid(generation, revision)) return;
        final source = AudioSource.uri(
          Uri.file(path),
          tag: _current!.occurrence,
        );
        await _player
            .setAudioSources(
              [source],
              initialIndex: 0,
              initialPosition: Duration.zero,
            )
            .timeout(loadTimeout);
        if (!_valid(generation, revision)) return;
        await _player.setLoopMode(LoopMode.off);
        if (_player.processingState != ProcessingState.ready) {
          throw StateError('Continuous recording did not become ready');
        }
      });
      if (!_valid(generation, revision)) return;
      _continuousLoaded = true;
      final duration = _player.duration;
      if (duration == null ||
          (duration.inMilliseconds - _continuousRepository.manifest!.durationMs)
                  .abs() >
              1000) {
        throw StateError('Continuous recording duration mismatch');
      }
      _installing = false;
      _download = const AudioDownloadState.idle();
      _continuousPositionChanged();
      if (_intent) {
        _startNative(generation, revision);
      } else {
        _phase = QuranPlaybackPhase.paused;
      }
      _publish();
    } catch (_) {
      if (_valid(generation, revision)) {
        await _fallbackContinuous(generation, revision);
      }
    }
  }

  void _continuousPositionChanged() {
    if (!_active || _installing || !_continuous) return;
    final next = _continuousRepository.manifest!.at(_player.position);
    if (identical(next, _interval) && _media != null) return;
    _tracker?.flush();
    _interval = next;
    final cursor = QuranPlaybackCursor(_plan!)
      ..index = ((next?.ayah ?? 1) - 1).clamp(0, 29)
      ..rangeCycle = _continuousCycle
      ..introduction = (next?.ayah ?? 1) <= 0;
    _cursor = cursor;
    _current = _QueueEntry(
      QuranAudioOccurrence(
        occurrenceId:
            '$_session:continuous:$_continuousCycle:${next?.ayah ?? "gap"}',
        item: cursor.item,
        cursor: cursor.copy(),
        sessionGeneration: _session,
      ),
    );
    _media = MediaItem(
      id: '$_session:continuous',
      title: next == null
          ? 'Al-Mulk · Full surah'
          : next.ayah == -1
          ? 'Al-Mulk · Isti’adhah'
          : cursor.item.label,
      album: 'Quran recitation',
      artist: _plan!.reciter.name,
      artUri: _artwork,
      duration: _player.duration,
      extras: {
        'surah': 67,
        if (next != null) 'ayah': next.ayah,
        'introduction': (next?.ayah ?? 1) <= 0,
        'repeat': _continuousCycle,
      },
    );
    _publish();
  }

  void _trackContinuousListening() {
    if (!_begun || !_active || _installing) return;
    final interval = _interval;
    _tracker?.sample(
      occurrence:
          '$_session:continuous:$_continuousCycle:${interval?.ayah ?? "gap"}',
      verse: '67:${interval?.ayah}',
      countVerse: (interval?.ayah ?? 0) > 0,
      position: interval == null
          ? _player.position
          : _player.position - interval.start,
      duration: interval?.duration,
      playing: audible && _player.playing,
    );
  }

  Future<void> _repeatContinuous() async {
    if (!_active || !_continuous || _installing) return;
    final generation = _session, revision = _revision;
    final plan = _plan!;
    final nextCycle = _continuousCycle + 1;
    if (!plan.infiniteRepeat && _continuousCycle >= plan.visibleRepeatCount) {
      _active = _intent = _begun = false;
      _phase = QuranPlaybackPhase.completed;
      _tracker?.flush();
      await _player.pause();
      _publish();
      return;
    }
    _installing = true;
    _starting = false;
    _playRequest++;
    _phase = _intent ? QuranPlaybackPhase.buffering : QuranPlaybackPhase.paused;
    _publish();
    try {
      await _player.pause().timeout(loadTimeout);
      if (!_valid(generation, revision)) return;
      // One file, one native item. Never rebuild an ayah queue at a cycle edge.
      await _player.seek(Duration.zero).timeout(loadTimeout);
      if (!_valid(generation, revision)) return;
      _continuousCycle++;
      _exhausted = false;
      _begun = false;
      _installing = false;
      _interval = null;
      _media = null;
      _tracker?.reset();
      _continuousPositionChanged();
      if (_intent) {
        _startNative(generation, revision);
      } else {
        _phase = QuranPlaybackPhase.paused;
      }
      _publish();
    } catch (_) {
      if (_valid(generation, revision)) {
        _continuousCycle = nextCycle;
        _continuousLoaded = false;
        await _fallbackContinuous(generation, revision);
      }
    }
  }

  Future<void> _navigateContinuous(bool next) async {
    if (!_active || _installing || _exhausted) return;
    final manifest = _continuousRepository.manifest!;
    // In an inter-ayah gap, navigation is relative to the preceding interval.
    final previous = manifest.intervals
        .where((i) => i.start <= _player.position)
        .lastOrNull;
    final ayah = previous?.ayah ?? 0;
    if (next && ayah >= 30) {
      if (!_plan!.infiniteRepeat &&
          _continuousCycle >= _plan!.visibleRepeatCount) {
        await stop();
        return;
      }
      _continuousCycle++;
      _continuousLoaded = false;
      await seek(Duration.zero);
      if (_continuous) _continuousLoaded = true;
    } else {
      final target = next ? (ayah + 1).clamp(1, 30) : (ayah - 1).clamp(1, 30);
      await seek(manifest.ayah(target).start);
    }
  }

  Future<void> _fallbackContinuous(int generation, int revision) async {
    if (!_continuous || !_valid(generation, revision)) return;
    final manifest = _continuousRepository.manifest!;
    final last = !_continuousLoaded
        ? null
        : manifest.intervals
              .where((i) => i.start <= _player.position)
              .lastOrNull;
    final ayah = (last?.ayah ?? 1).clamp(1, 30);
    final cycle = _continuousCycle;
    final introduction = last == null || last.ayah <= 0;
    // Synchronous guard against duplicate decoder failures.
    _continuous = false;
    _interval = null;
    _tracker?.reset();
    _installing = true;
    _starting = false;
    _playRequest++;
    final handoffRevision = ++_revision;
    _stall?.cancel();
    // Stop the only player before installing EveryAyah. Preserve plan, cycle,
    // session and pause intent. Different recordings cannot share seek offsets.
    await _native(() async {
      if (_valid(generation, handoffRevision)) await _player.stop();
    });
    if (!_valid(generation, handoffRevision)) return;
    _exhausted = false;
    _begun = false;
    _current = _waiting = _failed = null;
    _queue.clear();
    _pending.clear();
    final cursor =
        QuranPlaybackCursor(_plan!, introductionForSurah: _includeIntroduction)
          ..index = ayah - 1
          ..rangeCycle = cycle;
    cursor.introduction = introduction && cursor.needsIntroduction;
    await _install(_entry(cursor), generation, handoffRevision);
    if (_valid(generation, handoffRevision)) {
      _kickFill();
      if (_legacyPreparer == null) unawaited(downloadSelection(_plan!));
    }
  }
}
