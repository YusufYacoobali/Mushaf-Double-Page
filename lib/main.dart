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

// -------------------------
// App entry
// -------------------------

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[APP] main() started');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[APP] MyApp build()');
    return MaterialApp(
      title: 'Quran Viewer',
      theme: ThemeData(useMaterial3: true),
      home: const LoadingScreen(),
    );
  }
}

// -------------------------
// Image Viewer
// -------------------------

class MyPDFViewer extends StatefulWidget {
  const MyPDFViewer({super.key});

  @override
  State<MyPDFViewer> createState() => _MyPDFViewerState();
}

class _MyPDFViewerState extends State<MyPDFViewer> {
  static const int TOTAL_PAGES = 851;

  late Directory _docDir;
  PageController? _pageController;

  int _currentPage = 0;
  bool _isPortrait = true;
  bool _ready = false;

  // Scrollbar
  bool _isScrollbarVisible = true;
  Timer? _hideScrollbarTimer;

  final List<Bookmark> _bookmarks = [];

  // -------------------------
  // Init
  // -------------------------

  @override
  void initState() {
    super.initState();
    debugPrint('[INIT] initState()');

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _init();
  }

  Future<void> _init() async {
    debugPrint('[INIT] Initializing viewer...');
    _docDir = await getApplicationDocumentsDirectory();
    debugPrint('[INIT] Documents dir: ${_docDir.path}');

    await _loadBookmarks();
    await _loadCurrentPage();

    debugPrint('[INIT] Initial page: $_currentPage');

    _pageController = PageController(initialPage: _currentPage);

    _startHideScrollbarTimer();
    setState(() => _ready = true);

    debugPrint('[INIT] Viewer ready');
  }

  Future<void> _loadBookmarks() async {
    debugPrint('[BOOKMARK] Loading bookmarks...');
    final data = await StorageManager.getBookmarks();
    _bookmarks
      ..clear()
      ..addAll(data);
    debugPrint('[BOOKMARK] Loaded ${_bookmarks.length} bookmarks');
  }

  Future<void> _loadCurrentPage() async {
    _currentPage = await StorageManager.getCurrentPage();
    debugPrint('[STATE] Restored current page: $_currentPage');
  }

  // -------------------------
  // Helpers
  // -------------------------

  String imagePath(int page) {
    final p = (page + 1).toString();
    final path = '${_docDir.path}/quran/13line/quran_13line_tajweed-$p.webp';

    if (!File(path).existsSync()) {
      debugPrint('[ERROR] Missing image: $path');
    }

    return path;
  }

  int _pageCount(bool portrait) {
    final count = portrait ? TOTAL_PAGES : (TOTAL_PAGES / 2).ceil();
    debugPrint('[LAYOUT] Page count = $count (portrait=$portrait)');
    return count;
  }

  void _startHideScrollbarTimer() {
    _hideScrollbarTimer?.cancel();
    _hideScrollbarTimer = Timer(const Duration(seconds: 6), () {
      debugPrint('[UI] Hiding scrollbar');
      setState(() => _isScrollbarVisible = false);
    });
  }

  void _onScreenTap() {
    debugPrint('[UI] Screen tapped, showing controls');
    setState(() => _isScrollbarVisible = true);
    _startHideScrollbarTimer();
  }

  void _addBookmark() {
    final pageNumber =
    PageMapper.bookmarkAddMapper(_currentPage, _isPortrait);

    debugPrint('[BOOKMARK] Trying to add bookmark for page $pageNumber');

    if (_bookmarks.any((b) => b.pageNumber == pageNumber)) {
      debugPrint('[BOOKMARK] Already exists, skipping');
      return;
    }

    setState(() {
      _bookmarks.add(Bookmark(pageNumber: pageNumber));
    });

    StorageManager.saveBookmarks(_bookmarks);
    debugPrint('[BOOKMARK] Added');
  }

  @override
  void dispose() {
    debugPrint('[LIFECYCLE] dispose()');
    _hideScrollbarTimer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  // -------------------------
  // Page builders
  // -------------------------

  Widget _singlePage(int index) {
    debugPrint('[BUILD] Single page build index=$index');
    return InteractiveViewer(
      child: Image.file(
        File(imagePath(index)),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          debugPrint('[ERROR] Failed to load image index=$index');
          return const Center(child: Text('Image missing'));
        },
      ),
    );
  }

  Widget _doublePage(int index) {
    final left = index * 2;
    final right = left + 1;

    debugPrint('[BUILD] Double page index=$index left=$left right=$right');

    return Row(
      children: [
        Expanded(child: _image(left)),
        if (right < TOTAL_PAGES) Expanded(child: _image(right)),
      ],
    );
  }

  Widget _image(int page) {
    debugPrint('[BUILD] Image page=$page');
    return InteractiveViewer(
      child: Image.file(
        File(imagePath(page)),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          debugPrint('[ERROR] Image load failed page=$page');
          return const Center(child: Text('Image missing'));
        },
      ),
    );
  }

  // -------------------------
  // Build
  // -------------------------

  @override
  Widget build(BuildContext context) {
    debugPrint('[BUILD] build()');

    return Scaffold(
      body: OrientationBuilder(
        builder: (context, orientation) {
          final portraitNow = orientation == Orientation.portrait;

          if (_isPortrait != portraitNow && _pageController != null) {
            debugPrint('[ORIENTATION] Change detected -> portrait=$portraitNow');

            _currentPage = PageMapper.orientationMapper(
              _currentPage,
              portraitNow,
            );

            debugPrint('[ORIENTATION] Mapped page=$_currentPage');

            _pageController = PageController(initialPage: _currentPage);
            _isPortrait = portraitNow;
          }

          if (!_ready) {
            debugPrint('[STATE] Not ready yet');
            return const Center(child: CircularProgressIndicator());
          }

          final pageCount = _pageCount(_isPortrait);

          return Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: pageCount,
                onPageChanged: (page) {
                  debugPrint('[PAGE] Changed -> $page');
                  setState(() => _currentPage = page);
                  StorageManager.saveCurrentPage(page);
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
                  onTap: _onScreenTap,
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
                        '${pageCount - _currentPage}/$pageCount',
                        style: const TextStyle(
                          color: Color(0xFF025C32),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _currentPage.toDouble(),
                          min: 0,
                          max: (pageCount - 1).toDouble(),
                          onChanged: (v) {
                            final p = v.toInt();
                            debugPrint('[SLIDER] Jump to $p');
                            _pageController?.jumpToPage(p);
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
                          debugPrint('[NAV] Open settings');
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const Settings(),
                            ),
                          );
                          debugPrint('[NAV] Returned from settings');
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
    debugPrint('[MODAL] Opening bookmarks');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
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
                        debugPrint('[BOOKMARK] Removed ${bk.pageNumber}');
                        setState(() => _bookmarks.remove(bk));
                        StorageManager.saveBookmarks(_bookmarks);
                      },
                      onPagePressed: (bk) {
                        final page =
                        PageMapper.bookmarkGoToMapper(
                          bk.pageNumber,
                          _isPortrait,
                        );
                        debugPrint('[BOOKMARK] Jump to page $page');
                        _pageController?.jumpToPage(page);
                        setState(() => _currentPage = page);
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
