import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:mushaf_two_page/pages/settings.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mushaf_two_page/pages/bookmark.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/utils/page_mapper.dart';
import 'package:mushaf_two_page/pages/loading.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Viewer',
      theme: ThemeData(useMaterial3: true),
      home: const LoadingScreen(),
    );
  }
}

/// Main PDF viewer screen
class MyPDFViewer extends StatefulWidget {
  const MyPDFViewer({super.key});

  @override
  State<MyPDFViewer> createState() => _MyPDFViewerState();
}

class _MyPDFViewerState extends State<MyPDFViewer> {
  /// Controller provided by pdfx
  PdfController? _pdfController;

  int _totalPages = 0;
  int _currentPage = 0;

  // pdf version changes when going to settings to make widget rebuild
  int _pdfVersion = 0;

  //Scrollbar
  bool _isScrollbarVisible = true;
  Timer? _hideScrollbarTimer;

  // orientation vars
  bool _isPortrait = true;
  bool isOptimizedPortrait = true;
  bool isOptimizedLandscape = false;

  // When pdf file path changes eg portrait normal vs stretched
  bool _isPdfChanging = false;

  // When orientation changes
  bool _isOrientationChanging = false;
  bool _pdfReady = false;

  String? _portraitPath;
  String? _landscapePath;

  final List<Bookmark> _bookmarks = [];

  // -------------------------
  // Lifecycle
  // -------------------------

  @override
  void initState() {
    super.initState();

    /// Immersive full-screen experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initialize();
  }

  /// Initial logic
  Future<void> _initialize() async {
    _isOrientationChanging = false;
    _isPdfChanging = false;
    _pdfVersion = 0;

    await _loadPdfPaths();
    await _loadBookmarks();
    await _loadCurrentPage();

    await _initializePdfController();
    _startHideScrollbarTimer();

    setState(() => _pdfReady = true);
  }

  // -------------------------
  // Loading
  // -------------------------

  /// Initialize PDF controller with current path
  Future<void> _initializePdfController() async {
    final pdfPath = _isPortrait ? _portraitPath! : _landscapePath!;

    _pdfController = PdfController(
      document: PdfDocument.openFile(pdfPath),
      initialPage: _currentPage + 1, // pdfx uses 1-based indexing
    );
  }

  /// Dispose and reinitialize controller
  Future<void> _reinitializePdfController() async {
    _pdfController?.dispose();
    await _initializePdfController();
  }

  /// Resolve correct PDF file paths based on settings
  Future<void> _loadPdfPaths() async {
    isOptimizedPortrait = await StorageManager.getOptimizedPortrait();
    isOptimizedLandscape = await StorageManager.getOptimizedLandscape();

    final dir = await getApplicationDocumentsDirectory();

    final portraitName = isOptimizedPortrait
        ? 'quran_source_v_l_s.pdf'
        : 'quran_source_v.pdf';
    final landscapeName = 'quran_source_double_close.pdf';

    _portraitPath = File('${dir.path}/$portraitName').path;
    _landscapePath = File('${dir.path}/$landscapeName').path;
  }

  Future<void> _loadBookmarks() async {
    final data = await StorageManager.getBookmarks();
    _bookmarks
      ..clear()
      ..addAll(data);
  }

  /// Load last saved page
  Future<void> _loadCurrentPage() async {
    _currentPage = await StorageManager.getCurrentPage();
  }

  // -------------------------
  // Page Change Handler
  // -------------------------

  void _handlePageChanged(int page) {
    // page is 1-based from pdfx, convert to 0-based
    final pageIndex = page - 1;

    /// Ignore fake page changes
    if (_isOrientationChanging || _isPdfChanging) {
      _isPdfChanging = false;
      return;
    }

    if (pageIndex != _currentPage) {
      print('[ONPAGECHANGE] current page is now $pageIndex');
      setState(() => _currentPage = pageIndex);
      StorageManager.saveCurrentPage(pageIndex);
    }
  }

  // -------------------------
  // UI helpers
  // -------------------------

  /// Starts or resets the auto-hide scrollbar timer
  void _startHideScrollbarTimer() {
    _hideScrollbarTimer?.cancel();
    _hideScrollbarTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() => _isScrollbarVisible = false);
      }
    });
  }

  /// Show scrollbar when user taps screen
  void _onScreenTap() {
    setState(() => _isScrollbarVisible = true);
    _startHideScrollbarTimer();
  }

  void _addBookmark() {
    int pageNumber = PageMapper.bookmarkAddMapper(_currentPage, _isPortrait);

    if (_bookmarks.any((b) => b.pageNumber == pageNumber)) {
      print('[DEBUG] Page $pageNumber already bookmarked');
      return;
    }

    setState(() {
      _bookmarks.add(Bookmark(pageNumber: pageNumber));
    });
    StorageManager.saveBookmarks(_bookmarks);
    print('[DEBUG] Added bookmark: $pageNumber');
  }

  @override
  void dispose() {
    _hideScrollbarTimer?.cancel();
    _pdfController?.dispose();
    super.dispose();
  }

  // -------------------------
  // Build
  // -------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OrientationBuilder(
        builder: (context, orientation) {
          final portraitNow = orientation == Orientation.portrait;

          /// Detect orientation change
          if (_isPortrait != portraitNow) {
            _isPortrait = portraitNow;
            _isOrientationChanging = true;

            // Reinitialize controller with new orientation
            _reinitializePdfController().then((_) {
              _currentPage = PageMapper.orientationMapper(_currentPage, _isPortrait);
              _pdfController?.jumpToPage(_currentPage + 1); // 1-based

              Future.delayed(const Duration(milliseconds: 200), () {
                _isOrientationChanging = false;
              });

              print('[ORIENTATION] current page is now $_currentPage');
              setState(() {});
            });
          }

          if (!_pdfReady || _pdfController == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            children: [
              PdfView(
                key: ValueKey('${_isPortrait ? _portraitPath : _landscapePath}-$_pdfVersion'),
                controller: _pdfController!,
                scrollDirection: Axis.horizontal,
                pageSnapping: true,
                physics: const PageScrollPhysics(),
                onDocumentLoaded: (document) {
                  _totalPages = document.pagesCount;
                  print('[ONLOAD] Total pages: $_totalPages');
                  setState(() {});
                },
                onPageChanged: (page) {
                  _handlePageChanged(page);
                },
              ),

              /// Full-screen tap catcher for scrollbar visibility
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _onScreenTap,
                ),
              ),

              /// Bottom scrollbar + controls
              if (_isScrollbarVisible && _totalPages > 0)
                Positioned(
                  bottom: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      /// Page indicator (mapped to Mushaf numbering)
                      Text(
                        '${MediaQuery.of(context).orientation == Orientation.landscape
                            ? ((_totalPages - _currentPage) * 2 - 1)
                            : (_totalPages - _currentPage)}/${MediaQuery.of(context).orientation == Orientation.landscape
                            ? (_totalPages * 2 - 1)
                            : _totalPages}',
                        style: const TextStyle(
                          color: Color(0xFF025C32),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Expanded(
                        /// Page slider
                        child: Slider(
                          activeColor: const Color.fromARGB(255, 2, 92, 50),
                          thumbColor: const Color.fromARGB(255, 175, 132, 4),
                          inactiveColor: const Color(0xFFD9B44A),
                          value: _currentPage.toDouble(),
                          min: 0,
                          max: (_totalPages - 1).toDouble(),
                          onChanged: (v) {
                            final page = v.toInt();
                            _pdfController?.jumpToPage(page + 1); // 1-based
                          },
                        ),
                      ),

                      /// Bookmarks
                      IconButton(
                        icon: const Icon(Icons.bookmarks_rounded,
                            color: Color(0xFF025C32)),
                        onPressed: _showBookmarksModal,
                      ),

                      /// Settings
                      IconButton(
                        icon: const Icon(
                          Icons.settings,
                          color: Color(0xFF025C32),
                        ),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const Settings()),
                          );
                          print('[DEBUG] Returned from Settings');

                          /// Going into settings can change pdf
                          _isPdfChanging = true;
                          await _loadPdfPaths();
                          await _reinitializePdfController();
                          _pdfVersion++;
                          setState(() {});
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

  void _showBookmarksModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final screenHeight = MediaQuery.of(context).size.height;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Container(
                height: isLandscape
                    ? screenHeight * 0.85
                    : screenHeight * 0.65,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 235, 243, 236),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 14,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),

                    // Bookmark button
                    Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: const Color(0xFFFBFBFB),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            _addBookmark();
                            setModalState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 18,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.bookmark_add_rounded,
                                  color: Color(0xFF2A6767),
                                  size: 26,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Bookmark this page',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2A6767),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Bookmark list
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: _bookmarks.length,
                        itemBuilder: (context, i) {
                          final bookmark = _bookmarks[i];
                          return BookmarkWidget(
                            bookmark: bookmark,
                            onBookmarkToggled: (b) {
                              setState(() => _bookmarks.remove(b));
                              StorageManager.saveBookmarks(_bookmarks);
                              setModalState(() {});
                            },
                            onPagePressed: (b) {
                              final pdfPage = PageMapper.bookmarkGoToMapper(
                                b.pageNumber,
                                _isPortrait,
                              );
                              _pdfController?.jumpToPage(pdfPage + 1); // 1-based
                              setState(() => _currentPage = pdfPage);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}