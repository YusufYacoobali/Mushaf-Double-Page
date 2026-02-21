import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mushaf_two_page/pages/bookmark_modal.dart';
import 'package:mushaf_two_page/pages/page_view.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mushaf_two_page/pages/settings.dart';
import 'package:mushaf_two_page/pages/bookmark.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';
import 'package:mushaf_two_page/pages/loading.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _darkMode = false;
  bool _loaded = false;

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
      theme: _darkMode ? ThemeData.dark() : ThemeData.light(),
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
  static const int TOTAL_PAGES = 851;

  late Directory _docDir;
  late PageController _pageController;

  bool _ready = false;
  bool _isPortrait = true;

  double _pageScale = 0.8;

  /// 🔑 single source of truth
  int _logicalPage = 0; // 0-based mushaf page

  bool isOptimizedPortrait = false;
  bool isOptimizedLandscape = false;

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
    await _loadOptimizationSettings();
    await _loadBookmarks();

    _pageScale = await StorageManager.getPageScale();
    _logicalPage = await StorageManager.getCurrentPage();
    debugPrint('[STATE] restored logicalPage=$_logicalPage');

    final initialIndex =
    _pageIndexFromLogical(_logicalPage, _isPortrait);

    debugPrint(
      '[PAGECTRL] initial index=$initialIndex portrait=$_isPortrait',
    );

    _pageController = PageController(initialPage: initialIndex);

    _startHideScrollbarTimer();
    setState(() => _ready = true);
  }

  Future<void> _loadOptimizationSettings() async {
    isOptimizedPortrait = await StorageManager.getOptimizedPortrait();
    isOptimizedLandscape = await StorageManager.getOptimizedLandscape();

    debugPrint(
      '[SETTINGS] portraitOpt=$isOptimizedPortrait landscapeOpt=$isOptimizedLandscape',
    );
    setState(() {});
  }

  Future<void> _loadBookmarks() async {
    final data = await StorageManager.getBookmarks();
    _bookmarks
      ..clear()
      ..addAll(data);

    debugPrint('[BOOKMARK] loaded ${_bookmarks.length}');
  }

  void _increaseScale() {
    final newScale = (_pageScale + 0.05)
        .clamp(QuranPageView.minPageScale, QuranPageView.maxPageScale);

    setState(() => _pageScale = newScale);
    StorageManager.savePageScale(newScale); // ✅ ADD
  }

  void _decreaseScale() {
    final newScale = (_pageScale - 0.05)
        .clamp(QuranPageView.minPageScale, QuranPageView.maxPageScale);

    setState(() => _pageScale = newScale);
    StorageManager.savePageScale(newScale); // ✅ ADD
  }

  // -------------------------
  // Page mapping (CRITICAL)
  // -------------------------

  int _pageIndexFromLogical(int logical, bool portrait) {
    if (portrait) {
      debugPrint('[MAP] logical $logical -> index $logical (portrait)');
      return logical;
    }

    // left page must be odd (1-based)
    final left = logical.isOdd ? logical - 1 : logical;
    final index = left ~/ 2;

    debugPrint(
      '[MAP] logical $logical -> left=$left -> spreadIndex=$index (landscape)',
    );

    return index;
  }

  int _logicalFromPageIndex(int index, bool portrait) {
    final logical = portrait ? index : index * 2;

    debugPrint(
      '[MAP] index $index -> logical=$logical (portrait=$portrait)',
    );

    return logical;
  }

  int _pageCount(bool portrait) {
    final count =
    portrait ? TOTAL_PAGES : (TOTAL_PAGES / 2).ceil();

    debugPrint(
      '[LAYOUT] pageCount=$count portrait=$portrait',
    );

    return count;
  }

  String imagePath(int logicalPage) {
    return '${_docDir.path}/quran/13line/'
        'quran_13line_tajweed-${logicalPage + 1}.webp';
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
    setState(() => _isScrollbarVisible = true);
    _startHideScrollbarTimer();
  }

  void _addBookmark() {
    final pageNumber =
    PageMapper.bookmarkAddMapper(_logicalPage, _isPortrait);

    debugPrint(
      '[BOOKMARK] add logical=$_logicalPage mapped=$pageNumber',
    );

    if (_bookmarks.any((b) => b.pageNumber == pageNumber)) return;

    setState(() => _bookmarks.add(Bookmark(pageNumber: pageNumber)));
    StorageManager.saveBookmarks(_bookmarks);
  }

  // -------------------------
  // Build
  // -------------------------

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: OrientationBuilder(
        builder: (context, orientation) {
          final portraitNow =
              orientation == Orientation.portrait;

          if (_isPortrait != portraitNow) {
            debugPrint(
              '[ORIENTATION] change -> portrait=$portraitNow',
            );

            _isPortrait = portraitNow;

            final newIndex =
            _pageIndexFromLogical(_logicalPage, _isPortrait);

            debugPrint(
              '[ORIENTATION] logical=$_logicalPage -> newIndex=$newIndex',
            );

            _pageController.dispose();
            _pageController =
                PageController(initialPage: newIndex);
          }

          final pageCount = _pageCount(_isPortrait);

          return Stack(
            children: [
              PageView.builder(
                key: ValueKey(_isPortrait),
                controller: _pageController,
                itemCount: pageCount,
                onPageChanged: (index) {
                  debugPrint(
                    '[PAGE] changed index=$index',
                  );

                  setState(() {
                    _logicalPage =
                        _logicalFromPageIndex(index, _isPortrait);
                  });

                  debugPrint(
                    '[PAGE] logical now=$_logicalPage',
                  );

                  StorageManager.saveCurrentPage(_logicalPage);
                },
                itemBuilder: (context, index) {
                  return _isPortrait
                      ? QuranPageView.singlePage(
                    logicalPage: index,
                    pageScale: _pageScale,
                    imagePath: imagePath,
                  )
                      : QuranPageView.doublePage(
                    spreadIndex: index,
                    optimizedLandscape: isOptimizedLandscape,
                    imagePath: imagePath,
                    totalPages: TOTAL_PAGES,
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
                  child:  Material(
                    color: const Color.fromARGB(255, 235, 243, 236),
                    borderRadius: BorderRadius.circular(16),
                    elevation: 4,
                    child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                    children: [
                      Text(
                        '${PageMapper.sliderMapper(_logicalPage, _isPortrait)}/$TOTAL_PAGES',
                        style: const TextStyle(
                          color: Color(0xFF025C32),
                          fontWeight: FontWeight.w600,
                        ),

                      ),
                      Expanded(
                        child: Slider(
                          value: _pageIndexFromLogical(
                              _logicalPage, _isPortrait)
                              .toDouble(),
                          min: 0,
                          max: (pageCount - 1).toDouble(),
                          onChanged: (v) {
                            debugPrint(
                              '[SLIDER] jump index=${v.toInt()}',
                            );
                            setState(() {
                              _logicalPage =
                                  _logicalFromPageIndex(v.toInt(), _isPortrait);
                            });
                            _pageController
                                .jumpToPage(v.toInt());
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.bookmarks_rounded),
                        color: Color(0xFF025C32),
                        onPressed: (){ BookmarksModal.show(
                          context: context,
                          bookmarks: _bookmarks,
                          isPortrait: _isPortrait,
                          onAddBookmark: _addBookmark,
                          onRemoveBookmark: (b) {
                            setState(() => _bookmarks.remove(b));
                            StorageManager.saveBookmarks(_bookmarks);
                          },
                          onJumpToBookmark: (b) {
                            final page = PageMapper.bookmarkGoToMapper(
                              b.pageNumber,
                              _isPortrait,
                            );

                            _pageController.jumpToPage(page);

                            final logical =
                            _logicalFromPageIndex(page, _isPortrait);

                            setState(() => _logicalPage = logical);
                          });}
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove),
                        color: Color(0xFF025C32),
                        onPressed: _pageScale <= QuranPageView.minPageScale ? null : _decreaseScale,
                      ),
                      Text(
                        "${(_pageScale * 100).round()}%",
                        style: const TextStyle(
                          color: Color(0xFF025C32),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        color: Color(0xFF025C32),
                        onPressed: _pageScale >= QuranPageView.maxPageScale ? null : _increaseScale,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        color: Color(0xFF025C32),
                        onPressed: () async {
                          debugPrint('[SETTINGS] open');
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const Settings(),
                            ),
                          );
                          debugPrint(
                            '[SETTINGS] changed, reloading flags',
                          );
                          await _loadOptimizationSettings();
                          await MyApp.of(context)?.reloadTheme();
                        },
                      ),
                    ],
                  ),
                ),
                  ),
                )
            ],
          );
        },
      ),
    );
  }
}
