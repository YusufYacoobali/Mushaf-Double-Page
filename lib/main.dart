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
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/navigator.dart';
import 'package:mushaf_two_page/utils/reminder_notifications.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart' as surah_mapper;
import 'package:mushaf_two_page/utils/translation_manager.dart';
import 'package:mushaf_two_page/utils/surah_summary_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mushaf_two_page/pages/settings.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';
import 'package:mushaf_two_page/pages/loading.dart';

import 'components/nav_bar_icon.dart';
import 'components/translation_modal.dart';
import 'firebase_options.dart';

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
  } on MissingPluginException catch (e) {
    debugPrint(
      '[AUDIO] Background audio plugin not registered yet. '
      'Stop the app and run a fresh build after adding audio dependencies. $e',
    );
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
  bool _loaded = false;

  bool get darkMode => _darkMode;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    _darkMode = await StorageManager.getDarkMode();
    setState(() => _loaded = true);
  }

  Future<void> reloadTheme() async {
    final dark = await StorageManager.getDarkMode();
    setState(() => _darkMode = dark);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppPalette.forDarkMode(_darkMode).toThemeData(),
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

  // -------------------------
  // Init
  // -------------------------

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    debugPrint('[INIT] initState');
    _init();
  }

  Future<void> _init() async {
    debugPrint('[INIT] loading dirs / settings / state');

    _docDir = await getApplicationDocumentsDirectory();
    _mushaf = await StorageManager.getMushaf();
    await _loadBookmarks();

    _pageScalePortrait = await StorageManager.getPageScalePortrait();
    _pageScaleLandscape = await StorageManager.getPageScaleLandscape();

    _logicalPage = await StorageManager.getCurrentPage();
    debugPrint('[STATE] restored logicalPage=$_logicalPage');

    final initialIndex = PageMapper.pageIndexFromLogical(
      _logicalPage,
      _isPortrait,
    );

    debugPrint('[PAGECTRL] initial index=$initialIndex portrait=$_isPortrait');

    if (!mounted) return;

    _pageController = PageController(initialPage: initialIndex);
    _hasPageController = true;

    _startHideScrollbarTimer();
    await TranslationManager.load();
    await SurahSummaryManager.load();
    setState(() => _ready = true);
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

    debugPrint('[BOOKMARK] loaded ${_bookmarks.length}');
  }

  void _increaseScale() {
    setState(() {
      if (_isPortrait) {
        _pageScalePortrait = (_pageScalePortrait + 0.05).clamp(
          QuranPageView.minPageScalePortrait,
          QuranPageView.maxPageScalePortrait,
        );
        StorageManager.savePageScalePortrait(_pageScalePortrait);
      } else {
        _pageScaleLandscape = (_pageScaleLandscape + 0.05).clamp(
          QuranPageView.minPageScaleLandscape,
          QuranPageView.maxPageScaleLandscape,
        );
        StorageManager.savePageScaleLandscape(_pageScaleLandscape);
      }
    });
  }

  void _decreaseScale() {
    setState(() {
      if (_isPortrait) {
        _pageScalePortrait = (_pageScalePortrait - 0.05).clamp(
          QuranPageView.minPageScalePortrait,
          QuranPageView.maxPageScalePortrait,
        );
        StorageManager.savePageScalePortrait(_pageScalePortrait);
      } else {
        _pageScaleLandscape = (_pageScaleLandscape - 0.05).clamp(
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

    final count = portrait ? pages : (pages / 2).ceil();

    debugPrint('[LAYOUT] pageCount=$count portrait=$portrait');

    return count;
  }

  String imagePath(int logicalPage) {
    debugPrint('[MUSHAF] Current mushaf $_mushaf');
    final filePage = logicalPage.clamp(1, maxFilePage);
    return '${_docDir.path}/$_mushaf/$filePage.webp';
  }

  // -------------------------
  // UI helpers
  // -------------------------

  void _startHideScrollbarTimer() {
    _hideScrollbarTimer?.cancel();
    _hideScrollbarTimer = Timer(const Duration(seconds: 10), () {
      debugPrint('[UI] hide scrollbar');
      setState(() => _isScrollbarVisible = false);
    });
  }

  void _onScreenTap() {
    debugPrint('[UI] screen tap');

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

    debugPrint(
      '[BOOKMARK] add logical=$_logicalPage mapped=$pageNumber mushaf $_mushaf',
    );

    if (_bookmarks.any((b) => b.pageNumber == pageNumber)) return;

    setState(
      () => _bookmarks.add(Bookmark(pageNumber: pageNumber, mushaf: _mushaf)),
    );
    StorageManager.saveBookmarks(_bookmarks, mushaf: _mushaf);
  }

  void _showTranslationModal() {
    final surahs = surah_mapper.surahsFromLogicalPage(_logicalPage, _mushaf);
    TranslationModal.show(context, surahs);
  }

  void _showAudioModal() {
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
            debugPrint('[ORIENTATION] change -> portrait=$portraitNow');

            _isPortrait = portraitNow;

            final newIndex = PageMapper.pageIndexFromLogical(
              _logicalPage,
              _isPortrait,
            );

            debugPrint(
              '[ORIENTATION] logical=$_logicalPage -> newIndex=$newIndex',
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
                  debugPrint('[PAGE] changed index=$index');

                  setState(() {
                    _logicalPage = PageMapper.logicalFromPageIndex(
                      index,
                      _isPortrait,
                    );
                  });

                  debugPrint('[PAGE] logical now=$_logicalPage');

                  StorageManager.saveCurrentPage(
                    _logicalPage,
                    maxPage: maxFilePage,
                  );
                },
                itemBuilder: (context, index) {
                  return _isPortrait
                      ? QuranPageView.singlePage(
                          logicalPage: index,
                          pageScale: _pageScalePortrait,
                          imagePath: imagePath,
                          isDarkMode: darkMode,
                        )
                      : QuranPageView.doublePage(
                          spreadIndex: index,
                          pageScale: _pageScaleLandscape,
                          imagePath: imagePath,
                          totalPages: totalPages,
                          isDarkMode: darkMode,
                        );
                },
              ),

              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (_) => _onScreenTap(),
                ),
              ),

              AnimatedBuilder(
                animation: QuranAudioController.instance,
                builder: (context, _) {
                  return _miniAudioPlayer(palette);
                },
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
                                    //const SizedBox(width: 6),
                                    barIcon(
                                      icon: Icons.chat_outlined,
                                      palette: palette,
                                      onPressed: _showTranslationModal,
                                    ),
                                    //const SizedBox(width: 6),
                                    //const SizedBox(width: 6),
                                    barIcon(
                                      icon: Icons.menu_book_outlined,
                                      palette: palette,
                                      onPressed: () {
                                        SurahJuzNavigator.show(
                                          context: context,
                                          onJumpToPage: (page) {
                                            final actualPage =
                                            PageMapper.bookmarkGoToMapper(page, _isPortrait);

                                            _pageController.jumpToPage(actualPage);

                                            final logical = PageMapper.logicalFromPageIndex(
                                              actualPage,
                                              _isPortrait,
                                            );

                                            setState(() => _logicalPage = logical);
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
                                            setState(() => _bookmarks.remove(b));
                                            StorageManager.saveBookmarks(_bookmarks, mushaf: _mushaf);
                                          },
                                          onJumpToBookmark: (b) {
                                            Navigator.pop(context);

                                            final page =
                                            PageMapper.bookmarkGoToMapper(b.pageNumber, _isPortrait);

                                            _pageController.jumpToPage(page);

                                            final logical = PageMapper.logicalFromPageIndex(
                                              page,
                                              _isPortrait,
                                            );

                                            setState(() => _logicalPage = logical);
                                          },
                                        );
                                      },
                                    ),
                                    //const SizedBox(width: 6),
                                    barIcon(
                                      icon: Icons.settings,
                                      palette: palette,
                                      onPressed: () async {
                                        debugPrint('[SETTINGS] open');

                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const Settings()),
                                        );

                                        if (!context.mounted) return;

                                        await MyApp.of(context)?.reloadTheme();

                                        final mushaf = await StorageManager.getMushaf();
                                        if (!context.mounted) return;

                                        if (mushaf != _mushaf) {
                                          if (_mushaf == 'indopak_tajweed' && mushaf == 'madani') {
                                            _logicalPage = PageMapper.indoPakToMadani(_logicalPage);
                                          }

                                          if (_mushaf == 'madani' && mushaf == 'indopak_tajweed') {
                                            _logicalPage = PageMapper.madaniToIndoPak(_logicalPage);
                                          }

                                          final newIndex = PageMapper.pageIndexFromLogical(
                                            _logicalPage,
                                            _isPortrait,
                                          );

                                          setState(() => _mushaf = mushaf);
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

  Widget _miniAudioPlayer(AppPalette palette) {
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
      bottom: _isScrollbarVisible ? 98 : 22,
      child: Material(
        color: palette.readerBar,
        borderRadius: BorderRadius.circular(18),
        elevation: 8,
        shadowColor: palette.shadow,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _showAudioModal,
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
                  onPressed: _showAudioModal,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
