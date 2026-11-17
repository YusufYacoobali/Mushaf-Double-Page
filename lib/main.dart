import 'utils/ios_device_idiom.dart';
import 'utils/reader_layout.dart';
import 'utils/reader_paging.dart';
import 'utils/deferred_reminders.dart';
import 'utils/audio_vertical_follower.dart';
import 'components/adaptive_quran_pages.dart';
import 'utils/reader_highlight_preferences.dart';
import 'utils/audio_page_follower.dart';
import 'components/reader_audio_controls.dart';
import 'progress/app_time_tracker.dart';
import 'progress/journey_tracking.dart';
import 'package:mushaf_two_page/utils/app_motion.dart';
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'logic/quran_audio_handler.dart';
import 'package:mushaf_two_page/components/audio_modal.dart';
import 'package:mushaf_two_page/components/bookmark_modal.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/audio_preferences.dart';
import 'package:mushaf_two_page/utils/navigator.dart';
import 'package:mushaf_two_page/utils/reminder_notifications.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart' as surah_mapper;
import 'package:mushaf_two_page/utils/translation_manager.dart';
import 'package:mushaf_two_page/utils/translation_preferences.dart';
import 'package:mushaf_two_page/utils/surah_summary_manager.dart';
import 'package:mushaf_two_page/utils/page_ayah_index.dart';
import 'package:mushaf_two_page/utils/ayah_rect_index.dart';
import 'package:mushaf_two_page/progress/reading_progress_store.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mushaf_two_page/pages/settings.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';
import 'package:mushaf_two_page/pages/loading.dart';

import 'components/nav_bar_icon.dart';
import 'components/reader_dock.dart';
import 'progress/daily_reading_card.dart';
import 'components/translation_modal.dart';
import 'firebase_options.dart';
import 'utils/app_review.dart';
import 'utils/recent_surah_history.dart';
import 'utils/retired_audio_cache.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(removeRetiredAudioCache());
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initBackgroundAudio();
  // Never await optional notification setup before Flutter's first frame.
  // On iOS 27 its plugin initialization can wait indefinitely for a scene or
  // permissions; previously this trapped the app on the launch storyboard.
  runApp(const MyApp());
  scheduleDeferredReminders(ReminderNotifications.initialize);
}

Future<void> _initBackgroundAudio() async {
  try {
    await QuranAudioHandler.initialize();
  } on MissingPluginException {
    // Plugin not yet registered — requires a fresh build after adding audio deps.
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<MyAppState>();

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _darkMode = false;
  bool _appDarkMode = false;
  bool _loaded = false;

  bool get darkMode => _darkMode;
  bool get appDarkMode => _appDarkMode;

  @override
  void initState() {
    super.initState();
    AppTimeTracker.instance.start();
    AppReview.schedulePromptAfterOpen(
      () => _navigatorKey.currentContext,
      canShowPrompt: () =>
          _loaded &&
          AppReview.navigatorObserver.currentPageName == '/reader' &&
          _navigatorKey.currentState?.canPop() == false &&
          !QuranAudioController.instance.preparing &&
          QuranAudioController.instance.phase !=
              QuranPlaybackPhase.recovering &&
          QuranAudioController.instance.phase != QuranPlaybackPhase.buffering &&
          !QuranAudioController.instance.offlineDownloading &&
          QuranAudioController.instance.error == null,
    );
    _loadTheme();
  }

  @override
  void dispose() {
    AppReview.cancelScheduledPrompt();
    AppTimeTracker.instance.dispose();
    super.dispose();
  }

  Future<void> _loadTheme() async {
    _darkMode = await StorageManager.getDarkMode();
    _appDarkMode = await StorageManager.getAppDarkMode();
    setState(() => _loaded = true);
  }

  Future<void> reloadTheme() async {
    final dark = await StorageManager.getDarkMode();
    final appDark = await StorageManager.getAppDarkMode();
    setState(() {
      _darkMode = dark;
      _appDarkMode = appDark;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox();

    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [AppReview.navigatorObserver],
      debugShowCheckedModeBanner: false,
      theme: AppPalette.forTheme(
        mushafDark: _darkMode,
        appDark: _appDarkMode,
      ).toThemeData(),
      home: const LoadingScreen(),
    );
  }
}

class MyPDFViewer extends StatefulWidget {
  const MyPDFViewer({super.key});

  @override
  State<MyPDFViewer> createState() => _MyPDFViewerState();
}

class _MyPDFViewerState extends State<MyPDFViewer> with WidgetsBindingObserver {
  String _mushaf = 'indopak_tajweed';

  late Directory _docDir;
  ReaderPaging? _paging;
  PageController get _pageController => _paging!.controller;

  bool _ready = false;
  bool _isIPad = false;
  bool get _hasPageController => _paging != null;
  bool _singlePage = true;
  bool _bottomDock = true;
  bool _ayahHighlightingEnabled = true;
  bool _readerWhite = false;
  bool _controlsArrowOnly = false;
  bool _audioWasActive = false;
  bool _audioFollowScheduled = false;
  final _audioPageFollower = AudioPageFollower();
  late final AudioVerticalFollower _audioVerticalFollower;
  final _readerDockKey = GlobalKey();
  bool get _readerVisible =>
      mounted &&
      _ready &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
  ReadingProgress? _dailyWelcome;
  bool _recordingProgress = false;
  Timer? _welcomeTimer;

  double _pageScalePortrait = 0.8;
  double _pageScaleLandscape = 0.7; // slightly smaller to fit side-by-side

  /// 🔑 single source of truth
  int _logicalPage = 1;

  bool _isScrollbarVisible = true;
  Timer? _hideScrollbarTimer;

  final List<Bookmark> _bookmarks = [];
  late RecentSurahHistory _surahHistory;

  // The ayah currently highlighted on the page (tap selection / bookmark resume).
  int? _selPage;
  int _selSurah = 0;
  int _selAyah = 0;
  String? _savedHighlightIdentity;

  // -------------------------
  // Init
  // -------------------------

  @override
  void initState() {
    super.initState();
    _audioVerticalFollower = AudioVerticalFollower(
      canFollow: () => _readerVisible && QuranAudioController.instance.audible,
      obstructions: () {
        if (!_isScrollbarVisible) return const [];
        final dock = _readerDockKey.currentContext?.findRenderObject();
        return dock is RenderBox && dock.hasSize && dock.attached
            ? [
                MatrixUtils.transformRect(
                  dock.getTransformTo(null),
                  Offset.zero & dock.size,
                ),
              ]
            : const [];
      },
    );
    // Android owns status-bar visibility in MainActivity, including app resume.
    if (!Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    WidgetsBinding.instance.addObserver(this);
    QuranAudioController.instance.addListener(_audioChanged);
    _init();
  }

  Future<void> _init() async {
    // Resolve the native device family before exposing the reader, avoiding
    // a brief two-page iPad layout or a page-mode change after first paint.
    _isIPad = await IosDeviceIdiom.isIPad();
    _docDir = await getApplicationDocumentsDirectory();
    _mushaf = await StorageManager.getMushaf();
    _surahHistory = RecentSurahHistory(_mushaf);
    await _surahHistory.load();
    await _loadBookmarks();

    _readerWhite = await StorageManager.getReaderWhiteBackground();
    _controlsArrowOnly = await StorageManager.getControlsArrowOnly();
    _isScrollbarVisible = !_controlsArrowOnly;
    _pageScalePortrait = await StorageManager.getPageScalePortrait();
    _pageScaleLandscape = await StorageManager.getPageScaleLandscape();
    _ayahHighlightingEnabled =
        await StorageManager.getAyahHighlightingEnabled();

    _logicalPage = await StorageManager.getCurrentPage();

    if (!mounted) return;
    _paging = ReaderPaging(initialPage: _logicalPage, lastPage: maxFilePage)
      ..configure(ReaderPageMode.single);

    if (_isScrollbarVisible) _startHideScrollbarTimer();
    await TranslationManager.load();
    await SurahSummaryManager.load();
    await PageAyahIndex.load();
    _recordSurahVisit();
    await AyahRectIndex.load();
    final savedHighlight = await ReaderHighlightPreferences.load(_mushaf);
    if (!mounted) return;
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
    setState(() => _ready = true);
    _audioChanged();
    _persistHighlight();
    _recordProgress();
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    QuranAudioController.instance.removeListener(_audioChanged);
    _audioVerticalFollower.dispose();
    _hideScrollbarTimer?.cancel();
    _paging?.dispose();
    if (!Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _audioVerticalFollower.invalidate();
    if (state == AppLifecycleState.resumed && _ready) _recordProgress();
    if (state != AppLifecycleState.resumed && _ready) _persistHighlight();
  }

  Future<void> _loadBookmarks() async {
    final data = await StorageManager.getBookmarks(_mushaf);
    _bookmarks
      ..clear()
      ..addAll(data);
  }

  void _recordSurahVisit({int? surah}) {
    if (_surahHistory.visit(
      _firstVisiblePage,
      pagesPerView: _singlePage ? 1 : 2,
      surah: surah,
    )) {
      unawaited(_surahHistory.save());
    }
  }

  void _jumpToReadingPage(int page, {int? surah}) {
    _audioVerticalFollower.invalidate();
    final logical = page.clamp(1, maxFilePage);
    setState(() {
      _logicalPage = logical;
      _forgetAyahSelection();
      _recordSurahVisit(surah: surah);
    });
    unawaited(_paging!.goTo(logical));
    StorageManager.saveCurrentPage(logical, maxPage: maxFilePage);
    unawaited(_recordProgress());
  }

  void _increaseScale() => _adjustScale(0.05);
  void _decreaseScale() => _adjustScale(-0.05);

  void _adjustScale(double delta) {
    _audioVerticalFollower.invalidate();
    setState(() {
      if (_singlePage) {
        _pageScalePortrait = (_pageScalePortrait + delta).clamp(
          QuranPageView.minPageScalePortrait,
          QuranPageView.maxPageScalePortrait,
        );
        StorageManager.savePageScalePortrait(_pageScalePortrait);
      } else {
        _pageScaleLandscape = (_pageScaleLandscape + delta).clamp(
          QuranPageView.minPageScaleLandscape,
          QuranPageView.maxPageScaleLandscape,
        );
        StorageManager.savePageScaleLandscape(_pageScaleLandscape);
      }
    });
  }

  int get maxFilePage {
    if (_mushaf == 'madani') return PageMapper.madaniLastFilePage;
    return PageMapper.indopakLastFilePage;
  }

  int get totalPages {
    return maxFilePage + 1;
  }

  int get _firstVisiblePage =>
      PageMapper.visiblePages(_logicalPage, _singlePage, maxFilePage).first;

  String imagePath(int logicalPage) {
    final filePage = logicalPage.clamp(1, maxFilePage);
    return '${_docDir.path}/$_mushaf/$filePage.webp';
  }

  // -------------------------
  // UI helpers
  // -------------------------

  void _startHideScrollbarTimer() {
    _hideScrollbarTimer?.cancel();
    _hideScrollbarTimer = Timer(const Duration(seconds: 10), () {
      // An explicitly hidden dock stays hidden, but the timer must not remove
      // the playback controls while a recitation is running.
      if (QuranAudioController.instance.playing) return;
      if (mounted) setState(() => _isScrollbarVisible = false);
    });
  }

  void _onScreenTap() {
    // Clear the selection independently of whether taps can reveal controls.
    if (_selPage != null) {
      setState(_forgetAyahSelection);
      return;
    }

    if (_controlsArrowOnly) return;

    setState(() {
      _isScrollbarVisible = !_isScrollbarVisible;
    });

    if (_isScrollbarVisible) {
      _startHideScrollbarTimer();
    } else {
      _hideScrollbarTimer?.cancel();
    }
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

  void _audioChanged() {
    if (mounted && _ready) {
      final audio = QuranAudioController.instance;
      if (audio.hasActivePlayback) {
        _hideScrollbarTimer?.cancel();
        if (!_audioWasActive && !_controlsArrowOnly) _isScrollbarVisible = true;
      } else if (_audioWasActive && _isScrollbarVisible && _selPage == null) {
        _startHideScrollbarTimer();
      }
      _audioWasActive = audio.hasActivePlayback;
      _persistHighlight();
      setState(() {});
      _scheduleAudioPageFollow();
    }
  }

  void _scheduleAudioPageFollow() {
    if (_audioFollowScheduled) return;
    _audioFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _audioFollowScheduled = false;
      if (!mounted ||
          !_ready ||
          !_hasPageController ||
          !_pageController.hasClients) {
        return;
      }
      final audio = QuranAudioController.instance;
      final visible = _readerVisible;
      final target = _audioPageFollower.targetPage(
        playing: audio.audible,
        visible: visible,
        session: audio.playbackSessionId,
        cycle: audio.currentRepeat,
        surah: audio.currentSurah,
        ayah: audio.currentAyah,
        currentPage: _logicalPage,
        portrait: _singlePage,
        mushaf: _mushaf,
      );
      final vertical = _audioVerticalFollower.beginAyah(
        playing: audio.audible,
        visible: visible,
        session: audio.playbackSessionId,
        cycle: audio.currentRepeat,
        surah: audio.currentSurah,
        ayah: audio.currentAyah,
        mushaf: _mushaf,
      );
      if (target == null) {
        if (vertical != null) _audioVerticalFollower.reveal(vertical);
        return;
      }
      setState(() {
        _logicalPage = target;
        _recordSurahVisit();
      });
      final navigation = _paging!.goTo(
        target,
        animate: !AppMotion.reduced(context),
      );
      if (vertical != null) {
        unawaited(
          _audioVerticalFollower.revealAfterNavigation(vertical, navigation),
        );
      } else {
        unawaited(navigation);
      }
      unawaited(StorageManager.saveCurrentPage(target, maxPage: maxFilePage));
      unawaited(_recordProgress());
    });
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
      final audio = QuranAudioController.instance;
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
    final audio = QuranAudioController.instance;
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

  void _highlightAyah(int page, int surah, int ayah) {
    if (!_ayahHighlightingEnabled) return;
    if (!_controlsArrowOnly) _hideScrollbarTimer?.cancel();
    setState(() {
      _selPage = page;
      _selSurah = surah;
      _selAyah = ayah;
      if (!_controlsArrowOnly) _isScrollbarVisible = true;
    });
    _persistHighlight();
  }

  /// A tap on either page layout selects the ayah under the finger; a tap away
  /// from Quran text clears the selection or toggles the reader toolbar.
  void _onPageTap(int page, double nx, double ny) {
    if (_ayahHighlightingEnabled && AyahRectIndex.supportsMushaf(_mushaf)) {
      final hit = AyahRectIndex.hitTest(page, nx, ny, mushaf: _mushaf);
      if (hit != null) {
        if (_selPage != null &&
            _selSurah == hit.surah &&
            _selAyah == hit.ayah) {
          _hideScrollbarTimer?.cancel();
          setState(() {
            _forgetAyahSelection();
            _isScrollbarVisible = false;
          });
          return;
        }
        _highlightAyah(page, hit.surah, hit.ayah);
        return;
      }
    }
    if (_selPage != null) {
      setState(_forgetAyahSelection);
    } else {
      _onScreenTap();
    }
  }

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

  void _showTranslationModal({
    int? logicalPage,
    int? focusSurah,
    int? focusAyah,
  }) {
    final requestedPage = logicalPage ?? _logicalPage;
    final viewStartPage = _singlePage
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
      final pages = PageMapper.visiblePages(
        _logicalPage,
        _singlePage,
        maxFilePage,
      );
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
          onRemoveBookmark: (b) {
            setState(() => _bookmarks.remove(b));
            StorageManager.saveBookmarks(_bookmarks, mushaf: _mushaf);
          },
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
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const Settings()),
        );

        if (!mounted) return;

        await MyApp.of(context)?.reloadTheme();

        _readerWhite = await StorageManager.getReaderWhiteBackground();
        final ayahHighlighting =
            await StorageManager.getAyahHighlightingEnabled();
        final arrowOnly = await StorageManager.getControlsArrowOnly();
        if (!mounted) return;
        setState(() {
          if (arrowOnly && !_controlsArrowOnly) {
            _isScrollbarVisible = false;
            _hideScrollbarTimer?.cancel();
          }
          _controlsArrowOnly = arrowOnly;
          _ayahHighlightingEnabled = ayahHighlighting;
          if (!ayahHighlighting) {
            _forgetAyahSelection();
          }
        });

        final mushaf = await StorageManager.getMushaf();
        if (!mounted) return;

        if (mushaf != _mushaf) {
          _audioVerticalFollower.invalidate();
          if (_mushaf == 'indopak_tajweed' && mushaf == 'madani') {
            _logicalPage = PageMapper.indoPakToMadani(_logicalPage);
          }

          if (_mushaf == 'madani' && mushaf == 'indopak_tajweed') {
            _logicalPage = PageMapper.madaniToIndoPak(_logicalPage);
          }

          setState(() {
            _mushaf = mushaf;
            _paging!.lastPage = maxFilePage;
            _paging!.focusedPage = _logicalPage.clamp(1, maxFilePage);
            _paging!.configure(
              _singlePage ? ReaderPageMode.single : ReaderPageMode.spread,
              force: true,
            );
            _forgetAyahSelection();
          });
          _surahHistory = RecentSurahHistory(_mushaf);
          await _surahHistory.load();
          if (!mounted) return;
          _recordSurahVisit();
          await _loadBookmarks();
        }

        setState(() {});
      },
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

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final darkMode = MyApp.of(context)?.darkMode ?? false;
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: _readerWhite ? Colors.white : Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = ReaderLayout.resolve(
            size: constraints.biggest,
            padding: MediaQuery.paddingOf(context),
            displayFeatures: MediaQuery.displayFeaturesOf(context),
            pageAspectRatio: QuranPageView.aspectRatioForMushaf(_mushaf),
            preserveLegacyIPadPortrait: _isIPad,
            iosPhoneWidePortrait:
                Theme.of(context).platform == TargetPlatform.iOS && !_isIPad,
          );
          _paging!.configure(layout.pageMode);
          _singlePage = layout.singlePage;
          _bottomDock = layout.bottomDock;
          _logicalPage = _paging!.focusedPage;
          final audioControls = _readerAudioControls(palette);
          final overlay = layout.controlsRegion;
          return ReaderActivity(
            layoutIdentity: layout.pageMode,
            pages: [
              for (final p in _paging!.visiblePages)
                if (PageAyahIndex.surahsOnPage(p, mushaf: _mushaf).isNotEmpty)
                  '$_mushaf:$p',
            ],
            child: Stack(
              children: [
                AdaptiveQuranPages(
                  verticalFollower: _audioVerticalFollower,
                  mushaf: _mushaf,
                  paging: _paging!,
                  layout: layout,
                  singleScale: _pageScalePortrait,
                  spreadScale: _pageScaleLandscape,
                  imagePath: imagePath,
                  isDarkMode: darkMode,
                  aspectRatio: QuranPageView.aspectRatioForMushaf(_mushaf),
                  highlightFor: _highlightFor,
                  highlightColor: palette.accent.withValues(alpha: .26),
                  onTap: _onPageTap,
                  onBackgroundTap: _onScreenTap,
                  onFocus: (page) {
                    setState(() {
                      _logicalPage = page;
                      _recordSurahVisit(
                        surah: PageAyahIndex.surahsOnPage(
                          page,
                          mushaf: _mushaf,
                        ).firstOrNull,
                      );
                    });
                    unawaited(
                      StorageManager.saveCurrentPage(
                        page,
                        maxPage: maxFilePage,
                      ),
                    );
                  },
                  onPageChanged: (page) {
                    setState(() {
                      _logicalPage = page;
                      _recordSurahVisit();
                    });
                    unawaited(
                      StorageManager.saveCurrentPage(
                        page,
                        maxPage: maxFilePage,
                      ),
                    );
                    unawaited(_recordProgress());
                  },
                ),
                Positioned.fromRect(
                  rect: overlay.deflate(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 480,
                        maxHeight: overlay.height * .5,
                      ),
                      child: MotionSwitcher(
                        alignment: Alignment.topCenter,
                        offset: const Offset(0, -.12),
                        child: _dailyWelcome == null
                            ? const SizedBox.shrink(key: ValueKey('no-welcome'))
                            : DailyReadingCard(
                                key: const ValueKey('daily-welcome'),
                                streak: _dailyWelcome!.streak,
                                compact: true,
                                onClose: () =>
                                    setState(() => _dailyWelcome = null),
                              ),
                      ),
                    ),
                  ),
                ),
                ReaderDockOverlay(
                  layout: layout,
                  child: ReaderDock(
                    key: _readerDockKey,
                    contextControls:
                        audioControls ??
                        (_selPage == null
                            ? null
                            : _buildAyahContextRow(palette)),
                    placement: layout.dockPlacement,
                    expanded: _isScrollbarVisible,
                    onToggle: () {
                      setState(
                        () => _isScrollbarVisible = !_isScrollbarVisible,
                      );
                      if (_isScrollbarVisible) _startHideScrollbarTimer();
                    },
                    palette: palette,
                    zoom: _readerZoom(palette),
                    actions: _readerActions(palette),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
