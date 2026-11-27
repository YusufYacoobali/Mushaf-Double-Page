part of 'quran_audio_controller.dart';

ListeningTracker _journeyListeningTracker() => ListeningTracker(
  onListen: (verse) {
    unawaited(JourneyStore.recordListen(verse));
    unawaited(ReadingProgressStore.recordReadingActivity());
  },
  onSeconds: (seconds) =>
      unawaited(JourneyStore.recordTime(listening: seconds)),
);

/// Samples the presented occurrence on the backend's own clock.
extension _ListeningProgress on QuranAudioController {
  void _trackListening() {
    if (_pcmActive) {
      _trackPcmListening();
      return;
    }
    final entry = _current;
    if (!_begun || entry == null) return;
    _tracker?.sample(
      occurrence: entry.occurrence.occurrenceId,
      verse: '${entry.item.surah}:${entry.item.ayah}',
      countVerse: !entry.item.isIntroduction,
      position: _backend.position,
      duration: _backend.duration,
      playing: audible && _backend.playing,
    );
  }

  void _trackPcmListening() {
    final row = _pcmRow;
    if (!_begun || row == null || _installing || !_active) return;
    _tracker?.sample(
      occurrence: '$_session:pcm:${row.id}:$_pcmNavigation',
      verse: '55:${row.ayah}',
      countVerse: row.ayah != null,
      position: _pcmRelative(_backend.position),
      duration: _pcmProof!.time(row.endFrame) - _pcmProof!.time(row.startFrame),
      playing: audible && _backend.playing,
    );
  }
}
