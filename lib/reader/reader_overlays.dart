part of 'reader_screen.dart';

extension _ReaderOverlays on _MyPDFViewerState {
  Future<void> _playAyah(int surah, int ayah) async {
    final activePlan = QuranAudioController.instance.plan;
    final saved = activePlan == null ? await AudioPreferences.load() : null;
    final reciter =
        activePlan?.reciter ??
        quranReciters.firstWhere(
          (candidate) => candidate.id == saved?.reciterId,
          orElse: () => quranReciters.first,
        );
    QuranAudioController.instance.playPlan(
      AudioPlaybackPlan(
        reciter: reciter,
        surah: surah,
        fromAyah: ayah,
        toAyah: ayah,
        repeatCount: 1,
        repeatMode: AudioRepeatMode.range,
        sourceMode: AudioSourceMode.range,
      ),
    );
  }

  Widget _buildAyahContextRow(AppPalette palette) {
    final page = _selPage;
    if (page == null) return const SizedBox.shrink();
    final name = surah_mapper.surahNameFromNumber(_selSurah, _mushaf);
    final bookmarked = _bookmarks.any(
      (b) => b.isAyah && b.surahNumber == _selSurah && b.ayah == _selAyah,
    );

    return ReaderAudioControls(
      portrait: _bottomDock,
      reference: '$_selSurah:$_selAyah',
      title: '$_selSurah:$_selAyah · $name',
      subtitle: 'Selected ayah',
      palette: palette,
      playing: false,
      playbackActive: false,
      onPlayPause: () => _playAyah(_selSurah, _selAyah),
      onPrevious: () {},
      onNext: () {},
      onStop: null,
      onSettings: _showAudioModal,
      selection: ReaderAudioSelection(
        reference: '$_selSurah:$_selAyah',
        bookmarked: bookmarked,
        onBookmark: () =>
            _toggleAyahBookmark(_selSurah, _selAyah, page, !bookmarked),
        onTranslate: () => _showAyahTranslation(_selSurah, _selAyah),
      ),
    );
  }

  Future<void> _showAyahTranslation(int surah, int ayah) async {
    final preferences = await TranslationPreferences.load();
    final sources = preferences.translations
        .where(TranslationManager.sources.containsKey)
        .toList();
    if (sources.isEmpty) sources.add('Saheeh International');

    await Future.wait(sources.map(TranslationManager.loadSource));
    if (!mounted) return;

    final translations = <(String, String)>[
      for (final source in sources)
        (
          source,
          TranslationManager.getSurah(surah, source: source)[ayah] ?? '',
        ),
    ].where((entry) => entry.$2.trim().isNotEmpty).toList();
    final palette = AppPalette.of(context);
    final name = surah_mapper.surahNameFromNumber(surah, _mushaf);

    final translationsSeen = <String>{};
    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.style(context),
      context: context,
      barrierColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      // Modal useSafeArea excludes the bottom system navigation inset.
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Material(
            color: palette.scaffold,
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .48,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$name  •  $surah:$ayah',
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(
                            Icons.close_rounded,
                            color: palette.muted,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    if (translations.isEmpty)
                      Text(
                        'Translation unavailable.',
                        style: TextStyle(color: palette.muted, fontSize: 14),
                      )
                    else
                      for (
                        var index = 0;
                        index < translations.length;
                        index++
                      ) ...[
                        if (index > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1, color: palette.border),
                          ),
                        Text(
                          translations[index].$1,
                          style: TextStyle(
                            color: palette.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        TranslationExposure(
                          verse: '$surah:$ayah',
                          seen: translationsSeen,
                          child: Text(
                            translations[index].$2,
                            textDirection:
                                translations[index].$1.contains('Urdu')
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 15,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showTranslationModal({
    int? logicalPage,
    int? focusSurah,
    int? focusAyah,
  }) {
    final requestedPage = logicalPage ?? _logicalPage;
    final viewStartPage = _singlePage || (_paging?.book ?? false)
        ? requestedPage
        : PageMapper.logicalFromPageIndex(
            PageMapper.pageIndexFromLogical(requestedPage, false),
            false,
          );
    // Indexed mushafs show the exact ayahs on the current physical page;
    // unindexed editions fall back to the surah(s) that page belongs to.
    final bool hasContent;
    if (PageAyahIndex.supportsMushaf(_mushaf)) {
      hasContent = PageAyahIndex.hasPage(_mushaf, viewStartPage);
    } else {
      final surahs = surah_mapper.surahsFromLogicalPage(viewStartPage, _mushaf);
      hasContent = surahs.any((s) => s.surah > 0);
    }
    if (!hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No translation for this page'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    TranslationModal.show(
      context,
      logicalPage: viewStartPage,
      mushaf: _mushaf,
      // Landscape shows a two-page spread (this page + the next).
      pagesPerView: _singlePage ? 1 : 2,
      bookmarkedAyahs: {
        for (final b in _bookmarks.where((b) => b.isAyah))
          '${b.surahNumber}:${b.ayah}',
      },
      onToggleAyahBookmark: _toggleAyahBookmark,
      focusSurah: focusSurah,
      focusAyah: focusAyah,
    );
  }

  void _showAudioModal() {
    // Pre-select the indexed current page's (or landscape spread's) dominant
    // surah and ayah range so playback defaults to "this page".
    if (PageAyahIndex.supportsMushaf(_mushaf)) {
      final pages = _paging!.pagesFor(_logicalPage);
      final segments = PageAyahIndex.segmentsForPages(pages, mushaf: _mushaf);
      if (segments.isNotEmpty) {
        // The surah occupying the most ayahs on the page best represents it.
        final dominant = segments.reduce(
          (a, b) => (b[2] - b[1]) > (a[2] - a[1]) ? b : a,
        );
        AudioModal.show(
          context,
          initialSurah: dominant[0],
          initialFromAyah: dominant[1],
          initialToAyah: dominant[2],
        );
        return;
      }
    }

    final surahs = surah_mapper.surahsFromLogicalPage(_logicalPage, _mushaf);
    final pageSurahs = surahs.where((s) => s.surah > 0).toList();
    final initialSurah = pageSurahs.isEmpty ? 1 : pageSurahs.first.surah;
    AudioModal.show(context, initialSurah: initialSurah);
  }

  // -------------------------
  // Build
  // -------------------------

  List<Widget> _readerActions(AppPalette palette) => [
    barIcon(
      icon: Icons.headphones_rounded,
      palette: palette,
      compact: true,
      onPressed: _showAudioModal,
    ),
    barIcon(
      icon: Icons.chat_outlined,
      palette: palette,
      compact: true,
      onPressed: _showTranslationModal,
    ),
    barIcon(
      icon: Icons.menu_book_outlined,
      palette: palette,
      compact: true,
      onPressed: () {
        SurahJuzNavigator.show(
          context: context,
          currentLogicalPage: _logicalPage,
          currentSurah: _logicalPage >= 4 ? _surahHistory.current?.surah : null,
          onJumpToSurah: (surah, page) =>
              _jumpToReadingPage(page, surah: surah),
          onJumpToPage: (page) {
            _jumpToReadingPage(page);
          },
          mushaf: _mushaf,
        );
      },
    ),
    barIcon(
      icon: Icons.bookmarks_rounded,
      palette: palette,
      compact: true,
      onPressed: () {
        BookmarksModal.show(
          context: context,
          bookmarks: _bookmarks,
          isPortrait: _singlePage,
          mushaf: _mushaf,
          previousSurah: _surahHistory.previous,
          onJumpToPreviousSurah: (visit) =>
              _jumpToReadingPage(visit.page, surah: visit.surah),
          onAddBookmark: _addBookmark,
          onRemoveBookmark: _removeBookmark,
          onJumpToBookmark: (b) {
            Navigator.pop(context);

            _jumpToReadingPage(b.pageNumber, surah: b.surahNumber);

            // Resume: highlight the bookmarked ayah so you
            // can see where you left off.
            if (b.isAyah) {
              _highlightAyah(b.pageNumber, b.surahNumber!, b.ayah!);
            }
          },
        );
      },
    ),
    barIcon(
      icon: Icons.settings,
      palette: palette,
      compact: true,
      onPressed: _openSettings,
    ),
  ];

  Widget? _readerAudioControls(AppPalette palette) {
    final controller = QuranAudioController.instance;
    final plan = controller.plan;
    if (plan == null || !controller.hasActivePlayback) {
      return null;
    }
    final ayah = controller.currentAyah;
    final surah = controller.currentSurah ?? plan.surah;
    final repeat = controller.currentRepeat;
    final actionSurah = _selPage == null ? surah : _selSurah;
    final actionAyah = _selPage == null ? ayah : _selAyah;
    final actionPage =
        _selPage ??
        (actionAyah == null
            ? null
            : PageAyahIndex.pageOfAyah(
                actionSurah,
                actionAyah,
                mushaf: _mushaf,
              ));
    final differentSelection =
        _selPage != null && (actionSurah != surah || actionAyah != ayah);
    final bookmarked = _bookmarks.any(
      (b) => b.isAyah && b.surahNumber == actionSurah && b.ayah == actionAyah,
    );
    return ReaderAudioControls(
      portrait: _bottomDock,
      palette: palette,
      title: differentSelection
          ? '$actionSurah:$actionAyah · Selected'
          : ayah == null
          ? controller.currentItem?.label ?? plan.surahInfo.name
          : '$surah:$ayah · ${quranSurahs[surah - 1].name}',
      reference: ayah == null ? '$surah' : '$surah:$ayah',
      subtitle:
          '${controller.statusLabel} · ${differentSelection ? 'Playing $surah:$ayah · ' : ''}${plan.reciter.name}${repeat == null ? '' : ' · $repeat/${plan.repeatLabel}'}',
      playing: controller.playing,
      paused: controller.paused,
      preparingLabel: controller.preparing && !controller.paused
          ? controller.statusLabel
          : null,
      onPrevious: controller.seekPrevious,
      onPlayPause: controller.togglePlayPause,
      onNext: controller.seekNext,
      onStop: controller.stop,
      onSettings: _showAudioModal,
      selection: actionAyah == null || actionPage == null
          ? null
          : ReaderAudioSelection(
              reference: '$actionSurah:$actionAyah',
              bookmarked: bookmarked,
              onBookmark: () => _toggleAyahBookmark(
                actionSurah,
                actionAyah,
                actionPage,
                !bookmarked,
              ),
              onTranslate: () => _showAyahTranslation(actionSurah, actionAyah),
              onPlaySelected: differentSelection
                  ? () => _playAyah(actionSurah, actionAyah)
                  : null,
            ),
    );
  }

  Widget _readerZoom(AppPalette palette) => ReaderZoom(
    portrait: _bottomDock,
    palette: palette,
    scale: _singlePage ? _pageScalePortrait : _pageScaleLandscape,
    minimum: _singlePage
        ? QuranPageView.minPageScalePortrait
        : QuranPageView.minPageScaleLandscape,
    onDecrease: _decreaseScale,
    onIncrease: _increaseScale,
  );
}
