import 'dart:async';

import '../logic/quran_audio_controller.dart';
import 'audio_vertical_follower.dart';
import 'page_ayah_index.dart';
import 'reader_paging.dart';

/// Follows new playback verses without snapping back on unrelated player updates.
class AudioPageFollower {
  String? _lastVerse;

  int? targetPage({
    required bool playing,
    bool visible = true,
    required int session,
    required int? cycle,
    required int? surah,
    required int? ayah,
    required int currentPage,
    required bool portrait,
    required String mushaf,
    List<int>? visiblePages,
  }) {
    if (!playing || surah == null || ayah == null) return null;
    final identity = '$session:$cycle:$surah:$ayah:$mushaf';
    if (identity == _lastVerse) return null;
    if (!visible) {
      _lastVerse = identity;
      return null;
    }
    final target = PageAyahIndex.pageOfAyah(surah, ayah, mushaf: mushaf);
    if (target == null) return null;
    _lastVerse = identity;
    final firstVisible = portrait ? currentPage : (currentPage ~/ 2) * 2;
    // A straddling ayah keeps its currently focused portion, then prefers
    // another visible leaf over a turn back to its first indexed page.
    final pages = {
      currentPage,
      ...visiblePages ?? [firstVisible, if (!portrait) firstVisible + 1],
    };
    for (final page in pages) {
      for (final segment in PageAyahIndex.segmentsForPage(
        page,
        mushaf: mushaf,
      )) {
        if (segment[0] == surah && ayah >= segment[1] && ayah <= segment[2]) {
          return page == currentPage ? null : page;
        }
      }
    }
    return target;
  }

  /// The player only supplies its current verse. Its queue and transport never
  /// wait for page animation, image layout or vertical reveal.
  void followReader({
    required QuranAudioController audio,
    required ReaderPaging paging,
    required AudioVerticalFollower vertical,
    required bool visible,
    required bool animate,
    required String mushaf,
    required void Function(int page, bool changedSpread) onCommit,
  }) {
    if (!paging.ready) return;
    final request = vertical.beginAyah(
      playing: audio.audible,
      visible: visible,
      session: audio.playbackSessionId,
      cycle: audio.currentRepeat,
      surah: audio.currentSurah,
      ayah: audio.currentAyah,
      mushaf: mushaf,
    );
    final target = targetPage(
      playing: audio.audible,
      visible: visible,
      session: audio.playbackSessionId,
      cycle: audio.currentRepeat,
      surah: audio.currentSurah,
      ayah: audio.currentAyah,
      currentPage: paging.focusedPage,
      portrait: paging.singlePage,
      mushaf: mushaf,
      visiblePages: paging.visiblePages,
    );
    if (request == null) return;
    final previousFocus = paging.focusedPage;
    final page = target ?? previousFocus;
    final changedSpread = !paging.visiblePages.contains(page);
    final ownsCommand =
        page != paging.pendingTarget &&
        (changedSpread || paging.pendingTarget != null);
    final navigation = ownsCommand
        ? paging.goTo(page, animate: animate)
        : paging.whenSettled;
    final generation = paging.generation, operation = paging.operation;
    if (ownsCommand && page != previousFocus) {
      unawaited(
        navigation.then((committed) {
          if (committed && paging.isCurrentCommand(operation)) {
            onCommit(page, changedSpread);
          }
        }),
      );
    }
    unawaited(
      vertical.revealAfterNavigation(
        request,
        navigation,
        currentNavigation: () =>
            paging.generation == generation &&
            paging.operation == operation &&
            paging.settled &&
            paging.visiblePages.contains(page),
        onSettled: () {
          if (paging.focus(page)) onCommit(page, false);
        },
      ),
    );
  }
}
