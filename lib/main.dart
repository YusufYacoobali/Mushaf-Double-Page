import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mushaf_two_page/components/bookmark_modal.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/navigator.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart' as surah_mapper;
import 'package:mushaf_two_page/utils/translation_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mushaf_two_page/pages/settings.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';
import 'package:mushaf_two_page/pages/loading.dart';

import 'components/translation_modal.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
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
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.chat_outlined),
                                  color: palette.readerIcon,
                                  onPressed: () {
                                    _showTranslationModal();
                                  },
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: const Icon(Icons.menu_book_outlined),
                                  color: palette.readerIcon,
                                  onPressed: () {
                                    SurahJuzNavigator.show(
                                      context: context,
                                      onJumpToPage: (page) {
                                        final actualPage =
                                            PageMapper.bookmarkGoToMapper(
                                              page,
                                              _isPortrait,
                                            );
                                        _pageController.jumpToPage(actualPage);

                                        final logical =
                                            PageMapper.logicalFromPageIndex(
                                              actualPage,
                                              _isPortrait,
                                            );

                                        debugPrint(
                                          '[NAV] page returned $actualPage',
                                        );
                                        debugPrint(
                                          '[NAV] logical page returned $logical',
                                        );

                                        setState(() => _logicalPage = logical);
                                      },
                                      mushaf: _mushaf,
                                    );
                                  },
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: const Icon(Icons.bookmarks_rounded),
                                  color: palette.readerIcon,
                                  onPressed: () {
                                    BookmarksModal.show(
                                      context: context,
                                      bookmarks: _bookmarks,
                                      isPortrait: _isPortrait,
                                      onAddBookmark: _addBookmark,
                                      onRemoveBookmark: (b) {
                                        setState(() => _bookmarks.remove(b));
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

                                        debugPrint(
                                          '[BOOKMAKR] page returned $page',
                                        );
                                        debugPrint(
                                          '[BOOKMAKR] logical page returned $logical',
                                        );

                                        setState(() => _logicalPage = logical);
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: const Icon(Icons.settings),
                                  color: palette.readerIcon,
                                  onPressed: () async {
                                    debugPrint('[SETTINGS] open');
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const Settings(),
                                      ),
                                    );
                                    if (!context.mounted) return;
                                    debugPrint(
                                      '[SETTINGS] changed, reloading flags',
                                    );
                                    await MyApp.of(context)?.reloadTheme();

                                    final mushaf =
                                        await StorageManager.getMushaf();
                                    if (!context.mounted) return;
                                    debugPrint(
                                      '[MUSHAF] Current mushaf $_mushaf',
                                    );

                                    if (mushaf != _mushaf) {
                                      debugPrint(
                                        '[MUSHAF] Mushaf changed: $_mushaf -> $mushaf',
                                      );

                                      // convert page BEFORE switching mushaf
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
                                      });
                                      await _loadBookmarks();
                                      _pageController.jumpToPage(newIndex);
                                    }
                                    setState(() {});
                                  },
                                ),
                              ],
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
