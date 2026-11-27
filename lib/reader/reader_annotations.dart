part of 'reader_screen.dart';

mixin _ReaderAnnotations on State<MyPDFViewer> {
  late final _audio = widget.audioController ?? QuranAudioController.instance;
  String get _mushaf;
  int get _logicalPage;
  bool get _ayahHighlightingEnabled;

  ReadingProgress? _dailyWelcome;
  bool _recordingProgress = false;
  Timer? _welcomeTimer;
  final List<Bookmark> _bookmarks = [];
  // The ayah currently highlighted on the page (tap selection / bookmark resume).
  int? _selPage;
  int _selSurah = 0;
  int _selAyah = 0;
  String? _savedHighlightIdentity;

  Future<void> _loadBookmarks() async {
    final data = await StorageManager.getBookmarks(_mushaf);
    _bookmarks
      ..clear()
      ..addAll(data);
  }

  void _addBookmark() {
    final pageNumber = _logicalPage;
    if (_bookmarks.any((b) => !b.isAyah && b.pageNumber == pageNumber)) return;

    setState(
      () => _bookmarks.add(Bookmark(pageNumber: pageNumber, mushaf: _mushaf)),
    );
    StorageManager.saveBookmarks(_bookmarks, mushaf: _mushaf);
  }

  Future<void> _recordProgress() async {
    if (_recordingProgress) return;
    _recordingProgress = true;
    try {
      final welcome = await ReadingProgressStore.recordReadingActivity();
      if (!mounted || welcome == null) return;
      setState(() => _dailyWelcome = welcome);
      _welcomeTimer?.cancel();
      _welcomeTimer = Timer(const Duration(seconds: 9), () {
        if (mounted) setState(() => _dailyWelcome = null);
      });
    } finally {
      _recordingProgress = false;
    }
  }

  void _forgetAyahSelection() {
    _selPage = null;
    _persistHighlight();
  }

  void _persistHighlight() {
    SavedReaderHighlight? saved;
    if (_ayahHighlightingEnabled) {
      if (_selPage != null) {
        saved = SavedReaderHighlight(
          mushaf: _mushaf,
          page: _selPage!,
          surah: _selSurah,
          ayah: _selAyah,
        );
      }
      final audio = _audio;
      if (saved == null &&
          !audio.preparing &&
          audio.hasActivePlayback &&
          audio.currentSurah != null &&
          audio.currentAyah != null) {
        final page = PageAyahIndex.pageOfAyah(
          audio.currentSurah!,
          audio.currentAyah!,
          mushaf: _mushaf,
        );
        if (page != null) {
          saved = SavedReaderHighlight(
            mushaf: _mushaf,
            page: page,
            surah: audio.currentSurah!,
            ayah: audio.currentAyah!,
          );
        }
      }
    }
    if (_savedHighlightIdentity == saved?.identity) return;
    _savedHighlightIdentity = saved?.identity;
    unawaited(
      ReaderHighlightPreferences.save(saved).catchError((Object error) {
        debugPrint('[READER] Could not save highlighted ayah: $error');
      }),
    );
  }

  /// Playback highlighting is independent of the contextual tap selection.
  List<Rect> _highlightFor(int logicalPage) {
    final audio = _audio;
    if (audio.hasActivePlayback && audio.currentAyah == null) return const [];
    if (_ayahHighlightingEnabled &&
        !audio.preparing &&
        audio.hasActivePlayback &&
        audio.currentSurah != null &&
        audio.currentAyah != null) {
      final rects = AyahRectIndex.rectsFor(
        logicalPage,
        audio.currentSurah!,
        audio.currentAyah!,
        mushaf: _mushaf,
      );
      if (rects.isNotEmpty) return rects;
    }
    if (_ayahHighlightingEnabled &&
        _selPage != null &&
        AyahRectIndex.supportsMushaf(_mushaf)) {
      return AyahRectIndex.rectsFor(
        logicalPage,
        _selSurah,
        _selAyah,
        mushaf: _mushaf,
      );
    }
    return const [];
  }

  /// Add or remove a single-ayah bookmark (toggled from the translation view).
  void _toggleAyahBookmark(int surah, int ayah, int page, bool add) {
    setState(() {
      if (add) {
        final bookmarkPage =
            PageAyahIndex.pageOfAyah(surah, ayah, mushaf: _mushaf) ?? page;
        final b = Bookmark(
          pageNumber: bookmarkPage,
          mushaf: _mushaf,
          surahNumber: surah,
          ayah: ayah,
        );
        if (!_bookmarks.any((x) => x.sameAs(b))) _bookmarks.add(b);
      } else {
        _bookmarks.removeWhere(
          (x) => x.isAyah && x.surahNumber == surah && x.ayah == ayah,
        );
      }
    });
    StorageManager.saveBookmarks(_bookmarks, mushaf: _mushaf);
  }

  void _removeBookmark(Bookmark bookmark) {
    setState(() => _bookmarks.remove(bookmark));
    StorageManager.saveBookmarks(_bookmarks, mushaf: _mushaf);
  }

  void _restoreHighlight(
    SavedReaderHighlight? savedHighlight,
    int maxFilePage,
  ) {
    _savedHighlightIdentity = savedHighlight?.identity;
    if (_ayahHighlightingEnabled &&
        savedHighlight != null &&
        savedHighlight.page <= maxFilePage &&
        AyahRectIndex.rectsFor(
          savedHighlight.page,
          savedHighlight.surah,
          savedHighlight.ayah,
          mushaf: _mushaf,
        ).isNotEmpty) {
      _selPage = savedHighlight.page;
      _selSurah = savedHighlight.surah;
      _selAyah = savedHighlight.ayah;
      _savedHighlightIdentity = savedHighlight.identity;
    }
  }
}
