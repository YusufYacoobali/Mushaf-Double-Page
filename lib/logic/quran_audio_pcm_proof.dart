part of 'quran_audio_controller.dart';

/// A single prebuilt EveryAyah PCM source. This is the bounded ten-ayah Stage-A
/// proof, not a progressive producer for arbitrary ranges/repeats/queues.
extension _PcmProofPlayback on QuranAudioController {
  Duration _pcmRelative(Duration position) {
    final start = _pcmProof!.time(_pcmRow!.startFrame);
    final end = _pcmProof!.time(_pcmRow!.endFrame);
    return Duration(
      microseconds: (position - start).inMicroseconds.clamp(
        0,
        (end - start).inMicroseconds,
      ),
    );
  }

  void _pcmPositionChanged() {
    if (!_pcmActive || !_active || _installing) return;
    final row = _pcmProof!.at(_backend.position);
    if (row == null || (identical(row, _pcmRow) && _media != null)) return;
    _tracker?.flush();
    _pcmRow = row;
    final cursor = QuranPlaybackCursor(_plan!)
      ..index = (row.ayah ?? 1) - 1
      ..introduction = row.ayah == null;
    _cursor = cursor;
    _current = _QueueEntry(
      QuranAudioOccurrence(
        occurrenceId: '$_session:pcm:${row.id}:$_pcmNavigation',
        item: cursor.item,
        cursor: cursor.copy(),
        sessionGeneration: _session,
      ),
    );
    _media = MediaItem(
      id: _current!.occurrence.occurrenceId,
      title: cursor.item.label,
      album: 'Quran recitation',
      artist: _plan!.reciter.name,
      artUri: _artwork,
      duration: _pcmProof!.time(row.endFrame) - _pcmProof!.time(row.startFrame),
      extras: {
        'surah': 55,
        if (row.ayah != null) 'ayah': row.ayah,
        'introduction': row.ayah == null,
        'repeat': 1,
      },
    );
    _publish();
  }

  Future<void> _preparePcmProof(int generation, int revision) async {
    _pcmActive = true;
    _pcmLoaded = false;
    _pcmRow = null;
    _installing = true;
    _current = _entry(QuranPlaybackCursor(_plan!)..introduction = true);
    try {
      await _pcmProof!.verify();
      if (!_valid(generation, revision)) return;
      await _native(() async {
        if (!_valid(generation, revision)) return;
        await _backend
            .setAudioSources([
              AudioSource.file(_pcmProof!.path, tag: _current!.occurrence),
            ], initialPosition: Duration.zero)
            .timeout(loadTimeout);
        if (!_valid(generation, revision)) return;
        await _backend.setLoopMode(LoopMode.off);
        final duration = _backend.duration;
        if (_backend.processingState != ProcessingState.ready ||
            duration == null ||
            (duration - _pcmProof!.time(_pcmProof!.frames)).inMilliseconds
                    .abs() >
                10) {
          throw StateError('PCM proof duration/readiness mismatch');
        }
      });
      if (!_valid(generation, revision)) return;
      _pcmLoaded = true;
      _installing = false;
      _pcmPositionChanged();
      if (_intent) {
        _startNative(generation, revision);
      } else {
        _phase = QuranPlaybackPhase.paused;
      }
      _publish();
    } catch (_) {
      if (_valid(generation, revision)) {
        await _fallbackPcmProof(generation, revision);
      }
    }
  }

  Future<void> _seekPcm(Duration absolute) async {
    if (!_active || _installing) return;
    final generation = _session, revision = _revision;
    try {
      _pcmNavigation++;
      _pcmRow = null;
      _tracker?.flush();
      await _backend.seek(absolute).timeout(loadTimeout);
      if (!_valid(generation, revision)) return;
      _pcmPositionChanged();
      _trackListening();
      _publish();
    } catch (_) {
      if (_valid(generation, revision)) {
        await _fallbackPcmProof(generation, revision);
      }
    }
  }

  Future<void> _navigatePcm(bool next) async {
    if (!_active || _installing || _pcmRow == null) return;
    final rows = _pcmProof!.rows;
    final index = rows.indexOf(_pcmRow!);
    final target = next ? index + 1 : (index - 1).clamp(1, rows.length - 1);
    if (target >= rows.length) {
      await stop();
      return;
    }
    await _seekPcm(_pcmProof!.time(rows[target].startFrame));
  }

  Future<void> _fallbackPcmProof(int generation, int revision) async {
    if (!_pcmActive || !_valid(generation, revision)) return;
    final row = !_pcmLoaded
        ? _pcmProof!.rows.first
        : _pcmProof!.at(_backend.position) ?? _pcmRow ?? _pcmProof!.rows.first;
    _pcmActive = false;
    _pcmRow = null;
    _tracker?.reset();
    _installing = true;
    _starting = false;
    _playRequest++;
    final handoff = ++_revision;
    _stall?.cancel();
    await _native(() async {
      if (_valid(generation, handoff)) await _backend.stop();
    });
    if (!_valid(generation, handoff)) return;
    _begun = _exhausted = false;
    _current = _waiting = _failed = null;
    _queue.clear();
    _pending.clear();
    final cursor =
        QuranPlaybackCursor(_plan!, introductionForSurah: _includeIntroduction)
          ..index = (row.ayah ?? 1) - 1
          ..introduction = row.ayah == null;
    await _install(_entry(cursor), generation, handoff);
    if (_valid(generation, handoff)) {
      _kickFill();
      if (_legacyPreparer == null) unawaited(downloadSelection(_plan!));
    }
  }
}
