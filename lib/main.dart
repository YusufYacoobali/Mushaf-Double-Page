import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:mushaf_two_page/components/audio_modal.dart';
import 'package:mushaf_two_page/components/bookmark_modal.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/navigator.dart';
import 'package:mushaf_two_page/utils/reminder_notifications.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart' as surah_mapper;
import 'package:mushaf_two_page/utils/translation_manager.dart';
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
import 'components/translation_modal.dart';
import 'firebase_options.dart';
import 'utils/app_review.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _initBackgroundAudio();
  await ReminderNotifications.initialize();
  runApp(const MyApp());
}

Future<void> _initBackgroundAudio() async {
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.quran.quran_double_page.audio',
      androidNotificationChannelName: 'Quran audio',
      androidNotificationChannelDescription: 'Quran recitation playback',
      androidNotificationOngoing: true,
    );
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
  bool _darkMode = false;
  bool _appDarkMode = false;
  bool _loaded = false;

  bool get darkMode => _darkMode;
  bool get appDarkMode => _appDarkMode;

  @override
  void initState() {
    super.initState();
    _loadTheme();
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

class _MyPDFViewerState extends State<MyPDFViewer> {
  String _mushaf = 'indopak_tajweed';

  late Directory _docDir;
  late PageController _pageController;

  bool _ready = false;
  bool _hasPageController = false;
  bool _isPortrait = true;

  double _pageScalePortrait = 0.8;
  double _pageScaleLandscape = 0.7; // slightly smaller to fit side-by-side

  /// 🔑 single source of truth
  int _logicalPage = 1;

  bool _isScrollbarVisible = true;
  Timer? _hideScrollbarTimer;

  final List<Bookmark> _bookmarks = [];

  // The ayah currently highlighted on the page (tap selection / bookmark resume).
  int? _selPage;
  int _selSurah = 0;
  int _selAyah = 0;

  // -------------------------
  // Init
  // -------------------------

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _init();
  }

  Future<void> _init() async {
    _docDir = await getApplicationDocumentsDirectory();
    _mushaf = await StorageManager.getMushaf();
    await _loadBookmarks();

    _pageScalePortrait = await StorageManager.getPageScalePortrait();
    _pageScaleLandscape = await StorageManager.getPageScaleLandscape();

    _logicalPage = await StorageManager.getCurrentPage();

    final initialIndex = PageMapper.pageIndexFromLogical(
      _logicalPage,
      _isPortrait,
    );

    if (!mounted) return;

    _pageController = PageController(initialPage: initialIndex);
    _hasPageController = true;

    _startHideScrollbarTimer();
    await TranslationManager.load();
    await SurahSummaryManager.load();
    await PageAyahIndex.load();
    await AyahRectIndex.load();
    setState(() => _ready = true);
    _recordProgress();

    // Count this session and auto-prompt for a review at key milestones.
    AppReview.recordSessionAndMaybePrompt();
  }

  @override
  void dispose() {
    _hideScrollbarTimer?.cancel();
    if (_hasPageController) {
      _pageController.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    final data = await StorageManager.getBookmarks(_mushaf);
    _bookmarks
      ..clear()
      ..addAll(data);
  }

  void _increaseScale() => _adjustScale(0.05);
  void _decreaseScale() => _adjustScale(-0.05);

  void _adjustScale(double delta) {
    setState(() {
      if (_isPortrait) {
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

  int _pageCount(bool portrait) {
    final pages = totalPages;
    return portrait ? pages : (pages / 2).ceil();
  }

  String imagePath(int logicalPage) {
    final filePage = logicalPage.clamp(1, maxFilePage);
    return '${_docDir.path}/$_mushaf/$filePage.webp';
  }

  // -------------------------
  // UI helpers
  // -------------------------

  void _startHideScrollbarTimer() {
    _hideScrollbarTimer?.cancel();
    _hideScrollbarTimer = Timer(
      const Duration(seconds: 10),
      () => setState(() => _isScrollbarVisible = false),
    );
  }

  void _onScreenTap() {
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

  /// First/last content page (Al-Fatiha start .. last surah end) for the mushaf.
  ({int first, int last}) _contentBounds() {
    final ranges = surah_mapper.getSurahRanges(_mushaf);
    return (
      first: ranges.firstWhere((r) => r.surah == 1).start,
      last: ranges.last.end,
    );
  }

  void _recordProgress() {
    final b = _contentBounds();
    ReadingProgressStore.recordPageRead(
      _logicalPage,
      mushaf: _mushaf,
      firstContent: b.first,
      lastContent: b.last,
    );
  }

  /// Highlight rectangles for the page if it holds the selected ayah.
  List<Rect> _highlightFor(int logicalPage) {
    if (_selPage != null && AyahRectIndex.supportsMushaf(_mushaf)) {
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
    setState(() {
      _selPage = page;
      _selSurah = surah;
      _selAyah = ayah;
    });
  }

  /// A tap on either page layout selects the ayah under the finger; a tap away
  /// from Quran text clears the selection or toggles the reader toolbar.
  void _onPageTap(int page, double nx, double ny) {
    if (AyahRectIndex.supportsMushaf(_mushaf)) {
      final hit = AyahRectIndex.hitTest(page, nx, ny, mushaf: _mushaf);
      if (hit != null) {
        _highlightAyah(page, hit.surah, hit.ayah);
        _showAyahQuickActions(page, hit.surah, hit.ayah);
        return;
      }
    }
    if (_selPage != null) {
      setState(() => _selPage = null);
    } else {
      _onScreenTap();
    }
  }

  void _playAyah(int surah, int ayah) {
    final activePlan = QuranAudioController.instance.plan;
    QuranAudioController.instance.playPlan(
      AudioPlaybackPlan(
        reciter: activePlan?.reciter ?? quranReciters.first,
        surah: surah,
        fromAyah: ayah,
        toAyah: ayah,
        repeatCount: 1,
        repeatMode: AudioRepeatMode.range,
        sourceMode: AudioSourceMode.range,
      ),
    );
  }

  void _showAyahQuickActions(int page, int surah, int ayah) {
    final palette = AppPalette.of(context);
    final name = surah_mapper.surahNameFromNumber(surah, _mushaf);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bookmarked = _bookmarks.any(
          (b) => b.isAyah && b.surahNumber == surah && b.ayah == ayah,
        );
        return Container(
          decoration: BoxDecoration(
            color: palette.scaffold,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '$name  ·  $surah:$ayah',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _ayahAction(
                    palette,
                    icon: Icons.play_arrow_rounded,
                    label: 'Play',
                    onTap: () {
                      Navigator.pop(ctx);
                      _playAyah(surah, ayah);
                    },
                  ),
                  const SizedBox(width: 10),
                  _ayahAction(
                    palette,
                    icon: bookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    label: bookmarked ? 'Bookmarked' : 'Bookmark',
                    onTap: () {
                      _toggleAyahBookmark(surah, ayah, page, !bookmarked);
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(width: 10),
                  _ayahAction(
                    palette,
                    icon: Icons.chat_outlined,
                    label: 'Translate',
                    onTap: () {
                      Navigator.pop(ctx);
                      _showTranslationModal(
                        logicalPage: page,
                        focusSurah: surah,
                        focusAyah: ayah,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ayahAction(
    AppPalette palette, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            children: [
              Icon(icon, color: palette.accent),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
    final viewStartPage = _isPortrait
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
      pagesPerView: _isPortrait ? 1 : 2,
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
      final pages = _isPortrait
          ? [_logicalPage]
          : [_logicalPage, _logicalPage + 1];
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

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final darkMode = MyApp.of(context)?.darkMode ?? false;
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final portraitNow = orientation == Orientation.portrait;

          if (_isPortrait != portraitNow) {
            _isPortrait = portraitNow;
            final newIndex = PageMapper.pageIndexFromLogical(
              _logicalPage,
              _isPortrait,
            );
            _pageController.dispose();
            _pageController = PageController(initialPage: newIndex);
          }

          final pageCount = _pageCount(_isPortrait);

          return Stack(
            children: [
              PageView.builder(
                key: ValueKey(_isPortrait),
                controller: _pageController,
                reverse: true,
                physics: const ClampingScrollPhysics(),
                itemCount: pageCount,
                onPageChanged: (index) {
                  setState(() {
                    _logicalPage = PageMapper.logicalFromPageIndex(
                      index,
                      _isPortrait,
                    );
                  });
                  StorageManager.saveCurrentPage(
                    _logicalPage,
                    maxPage: maxFilePage,
                  );
                  _recordProgress();
                },
                itemBuilder: (context, index) {
                  return _isPortrait
                      ? QuranPageView.singlePage(
                          logicalPage: index,
                          pageScale: _pageScalePortrait,
                          imagePath: imagePath,
                          isDarkMode: darkMode,
                          aspectRatio: QuranPageView.aspectRatioForMushaf(
                            _mushaf,
                          ),
                          highlightRects: _highlightFor(index),
                          highlightColor: palette.accent.withValues(alpha: .26),
                          onTap: _onPageTap,
                          onBackgroundTap: _onScreenTap,
                        )
                      : QuranPageView.doublePage(
                          spreadIndex: index,
                          pageScale: _pageScaleLandscape,
                          imagePath: imagePath,
                          totalPages: totalPages,
                          isDarkMode: darkMode,
                          aspectRatio: QuranPageView.aspectRatioForMushaf(
                            _mushaf,
                          ),
                          highlightFor: _highlightFor,
                          highlightColor: palette.accent.withValues(alpha: .26),
                          onTap: _onPageTap,
                          onBackgroundTap: _onScreenTap,
                        );
                },
              ),

              if (_isScrollbarVisible)
                AnimatedBuilder(
                  animation: QuranAudioController.instance,
                  builder: (context, _) => _MiniAudioPlayer(
                    palette: palette,
                    onTap: _showAudioModal,
                  ),
                ),

              if (_isScrollbarVisible)
                Positioned(
                  bottom: 24,
                  left: 10,
                  right: 10,
                  child: Material(
                    color: palette.readerBar,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 4,
                    shadowColor: palette.shadow,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 6,
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove),
                                  color: palette.readerIcon,
                                  onPressed:
                                      (_isPortrait
                                              ? _pageScalePortrait
                                              : _pageScaleLandscape) <=
                                          (_isPortrait
                                              ? QuranPageView
                                                    .minPageScalePortrait
                                              : QuranPageView
                                                    .minPageScaleLandscape)
                                      ? null
                                      : _decreaseScale,
                                ),

                                Text(
                                  "${((_isPortrait ? _pageScalePortrait : _pageScaleLandscape) * 100).round()}%",
                                  style: TextStyle(
                                    color: palette.readerIcon,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),

                                IconButton(
                                  icon: const Icon(Icons.add),
                                  color: palette.readerIcon,
                                  onPressed:
                                      (_isPortrait
                                              ? _pageScalePortrait
                                              : _pageScaleLandscape) >=
                                          (_isPortrait
                                              ? QuranPageView
                                                    .maxPageScalePortrait
                                              : QuranPageView
                                                    .maxPageScaleLandscape)
                                      ? null
                                      : _increaseScale,
                                ),
                              ],
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: Row(
                                  children: [
                                    barIcon(
                                      icon: Icons.headphones_rounded,
                                      palette: palette,
                                      onPressed: _showAudioModal,
                                    ),
                                    barIcon(
                                      icon: Icons.chat_outlined,
                                      palette: palette,
                                      onPressed: _showTranslationModal,
                                    ),
                                    barIcon(
                                      icon: Icons.menu_book_outlined,
                                      palette: palette,
                                      onPressed: () {
                                        SurahJuzNavigator.show(
                                          context: context,
                                          onJumpToPage: (page) {
                                            final actualPage =
                                                PageMapper.bookmarkGoToMapper(
                                                  page,
                                                  _isPortrait,
                                                );

                                            _pageController.jumpToPage(
                                              actualPage,
                                            );

                                            final logical =
                                                PageMapper.logicalFromPageIndex(
                                                  actualPage,
                                                  _isPortrait,
                                                );

                                            setState(
                                              () => _logicalPage = logical,
                                            );
                                          },
                                          mushaf: _mushaf,
                                        );
                                      },
                                    ),
                                    barIcon(
                                      icon: Icons.bookmarks_rounded,
                                      palette: palette,
                                      onPressed: () {
                                        BookmarksModal.show(
                                          context: context,
                                          bookmarks: _bookmarks,
                                          isPortrait: _isPortrait,
                                          onAddBookmark: _addBookmark,
                                          onRemoveBookmark: (b) {
                                            setState(
                                              () => _bookmarks.remove(b),
                                            );
                                            StorageManager.saveBookmarks(
                                              _bookmarks,
                                              mushaf: _mushaf,
                                            );
                                          },
                                          onJumpToBookmark: (b) {
                                            Navigator.pop(context);

                                            final page =
                                                PageMapper.bookmarkGoToMapper(
                                                  b.pageNumber,
                                                  _isPortrait,
                                                );

                                            _pageController.jumpToPage(page);

                                            final logical =
                                                PageMapper.logicalFromPageIndex(
                                                  page,
                                                  _isPortrait,
                                                );

                                            setState(
                                              () => _logicalPage = logical,
                                            );

                                            // Resume: highlight the bookmarked ayah so you
                                            // can see where you left off.
                                            if (b.isAyah) {
                                              _highlightAyah(
                                                b.pageNumber,
                                                b.surahNumber!,
                                                b.ayah!,
                                              );
                                            }
                                          },
                                        );
                                      },
                                    ),
                                    barIcon(
                                      icon: Icons.settings,
                                      palette: palette,
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const Settings(),
                                          ),
                                        );

                                        if (!context.mounted) return;

                                        await MyApp.of(context)?.reloadTheme();

                                        final mushaf =
                                            await StorageManager.getMushaf();
                                        if (!context.mounted) return;

                                        if (mushaf != _mushaf) {
                                          if (_mushaf == 'indopak_tajweed' &&
                                              mushaf == 'madani') {
                                            _logicalPage =
                                                PageMapper.indoPakToMadani(
                                                  _logicalPage,
                                                );
                                          }

                                          if (_mushaf == 'madani' &&
                                              mushaf == 'indopak_tajweed') {
                                            _logicalPage =
                                                PageMapper.madaniToIndoPak(
                                                  _logicalPage,
                                                );
                                          }

                                          final newIndex =
                                              PageMapper.pageIndexFromLogical(
                                                _logicalPage,
                                                _isPortrait,
                                              );

                                          setState(() {
                                            _mushaf = mushaf;
                                            _selPage = null;
                                          });
                                          await _loadBookmarks();
                                          _pageController.jumpToPage(newIndex);
                                        }

                                        setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MiniAudioPlayer extends StatelessWidget {
  final AppPalette palette;
  final VoidCallback onTap;

  const _MiniAudioPlayer({required this.palette, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final controller = QuranAudioController.instance;
    final plan = controller.plan;
    final ayah = controller.currentAyah;
    final repeat = controller.currentRepeat;

    if (plan == null ||
        controller.processingState == ProcessingState.idle ||
        controller.processingState == ProcessingState.completed) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 12,
      right: 12,
      bottom: 98,
      child: Material(
        color: palette.readerBar,
        borderRadius: BorderRadius.circular(18),
        elevation: 8,
        shadowColor: palette.shadow,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: palette.accentSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.headphones_rounded,
                    color: palette.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ayah == null
                            ? plan.surahInfo.name
                            : '${plan.surahInfo.name}:$ayah',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.readerIcon,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${plan.reciter.name}'
                        '${repeat == null ? '' : ' \u2022 $repeat/${plan.repeatLabel}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.readerIcon.withValues(alpha: .72),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Previous ayah',
                  icon: const Icon(Icons.skip_previous_rounded),
                  color: palette.readerIcon,
                  onPressed: controller.seekPrevious,
                ),
                IconButton(
                  tooltip: controller.playing ? 'Pause' : 'Play',
                  icon: Icon(
                    controller.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  color: palette.readerIcon,
                  onPressed: controller.togglePlayPause,
                ),
                IconButton(
                  tooltip: 'Next ayah',
                  icon: const Icon(Icons.skip_next_rounded),
                  color: palette.readerIcon,
                  onPressed: controller.seekNext,
                ),
                IconButton(
                  tooltip: 'Audio settings',
                  icon: const Icon(Icons.tune_rounded),
                  color: palette.readerIcon,
                  onPressed: onTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
