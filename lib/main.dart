import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mushaf_two_page/pages/settings.dart';
import 'package:mushaf_two_page/pages/bookmark.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';
import 'package:mushaf_two_page/pages/loading.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[APP] start');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoadingScreen(),
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
  }

  Future<void> _loadBookmarks() async {
    final data = await StorageManager.getBookmarks();
    _bookmarks
      ..clear()
      ..addAll(data);

    debugPrint('[BOOKMARK] loaded ${_bookmarks.length}');
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
  // Page widgets
  // -------------------------

  Widget _singlePage(int logicalPage) {
    debugPrint('[BUILD] single logical=$logicalPage');

    return InteractiveViewer(
      panEnabled: false,
      minScale: 1,
      maxScale: 3,
      child: Image.file(
        File(imagePath(logicalPage)),
        fit: isOptimizedPortrait ? BoxFit.fill : BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  Widget _doublePage(int spreadIndex) {
    final left = spreadIndex * 2;
    final right = left + 1;

    debugPrint(
      '[BUILD] spread=$spreadIndex left=$left right=$right',
    );

    if (!isOptimizedLandscape) {
      return InteractiveViewer(
        panEnabled: false,
        minScale: 1,
        maxScale: 3,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.file(File(imagePath(left))),
            const SizedBox(width: 2),
            if (right < TOTAL_PAGES)
              Image.file(File(imagePath(right))),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Row(
        children: [
          Expanded(
            child: Image.file(
              File(imagePath(left)),
              fit: BoxFit.fitWidth,
            ),
          ),
          const SizedBox(width: 4),
          if (right < TOTAL_PAGES)
            Expanded(
              child: Image.file(
                File(imagePath(right)),
                fit: BoxFit.fitWidth,
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------
  // UI helpers
  // -------------------------

  void _startHideScrollbarTimer() {
    _hideScrollbarTimer?.cancel();
    _hideScrollbarTimer = Timer(const Duration(seconds: 6), () {
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

                  _logicalPage =
                      _logicalFromPageIndex(index, _isPortrait);

                  debugPrint(
                    '[PAGE] logical now=$_logicalPage',
                  );

                  StorageManager.saveCurrentPage(_logicalPage);
                },
                itemBuilder: (context, index) {
                  return _isPortrait
                      ? _singlePage(index)
                      : _doublePage(index);
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
                  bottom: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Text(
                        '${_logicalPage + 1}/$TOTAL_PAGES',
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
                            _pageController
                                .jumpToPage(v.toInt());
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.bookmarks_rounded),
                        onPressed: _showBookmarksModal,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        onPressed: () async {
                          debugPrint('[SETTINGS] open');
                          final changed =
                          await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const Settings(),
                            ),
                          );
                          if (changed == true) {
                            debugPrint(
                              '[SETTINGS] changed, reloading flags',
                            );
                            await _loadOptimizationSettings();
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // -------------------------
  // Bookmarks modal
  // -------------------------

  void _showBookmarksModal() {
    debugPrint('[BOOKMARK] open modal');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Column(
            children: [
              ElevatedButton(
                onPressed: _addBookmark,
                child: const Text('Bookmark this page'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _bookmarks.length,
                  itemBuilder: (context, i) {
                    final b = _bookmarks[i];
                    return BookmarkWidget(
                      bookmark: b,
                      onBookmarkToggled: (bk) {
                        debugPrint(
                          '[BOOKMARK] remove ${bk.pageNumber}',
                        );
                        setState(() => _bookmarks.remove(bk));
                        StorageManager.saveBookmarks(_bookmarks);
                      },
                      onPagePressed: (bk) {
                        final logical =
                        PageMapper.bookmarkGoToMapper(
                          bk.pageNumber,
                          _isPortrait,
                        );

                        final index =
                        _pageIndexFromLogical(
                          logical,
                          _isPortrait,
                        );

                        debugPrint(
                          '[BOOKMARK] goto page=$logical index=$index',
                        );

                        _logicalPage = logical;
                        _pageController.jumpToPage(index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
