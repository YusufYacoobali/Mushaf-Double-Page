import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
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

class MyPDFViewer extends StatefulWidget {
  const MyPDFViewer({super.key});

  @override
  State<MyPDFViewer> createState() => _MyPDFViewerState();
}

class _MyPDFViewerState extends State<MyPDFViewer> {
  PDFViewController? _pdfController;

  int _totalPages = 0; // PDF pages
  int _currentPage = 0;

  bool _isPortrait = true;
  bool _isScrollbarVisible = true;
  Timer? _hideScrollbarTimer;


  bool isOptimizedPortrait = true;
  bool isOptimizedLandscape = false;

  bool _isPdfChanging = false;
  bool _isOrientationChanging = false;
  bool _pdfReady = false;
  int _pdfVersion = 0;

  FitPolicy fitPolicy = FitPolicy.BOTH;

  String? _portraitPath;
  String? _landscapePath;

  final List<Bookmark> _bookmarks = [];

  // -------------------------
  // Lifecycle
  // -------------------------

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initialize();
  }

  Future<void> _initialize() async {
    _isOrientationChanging = false;
    _isPdfChanging = false;
    _pdfVersion = 0;

    await _loadPdfPaths();
    await _loadBookmarks();
    await _loadCurrentPage();

    fitPolicy = _calculateFitPolicy();
    _startHideScrollbarTimer();

    setState(() => _pdfReady = true);
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

  void _removeBookmark(Bookmark bookmark) {
    setState(() {
      _bookmarks.remove(bookmark);
    });
    StorageManager.saveBookmarks(_bookmarks);
    print('[DEBUG] Removed bookmark: ${bookmark.pageNumber}');
  }

  @override
  void dispose() {
    _hideScrollbarTimer?.cancel();
    super.dispose();
  }

  // -------------------------
  // Loading
  // -------------------------
  Future<void> _loadPdfPaths() async {
    isOptimizedPortrait = await StorageManager.getOptimizedPortrait();
    isOptimizedLandscape = await StorageManager.getOptimizedLandscape();

    final dir = await getApplicationDocumentsDirectory();

    final portraitName =
    isOptimizedPortrait ? 'quran_source_v_l_s.pdf' : 'quran_source_v.pdf';
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

  Future<void> _loadCurrentPage() async {
    _currentPage = await StorageManager.getCurrentPage();
  }

  FitPolicy _calculateFitPolicy() {
    return (!_isPortrait && isOptimizedLandscape)
        ? FitPolicy.WIDTH
        : FitPolicy.BOTH;
  }

  // -------------------------
  // UI helpers
  // -------------------------

  void _startHideScrollbarTimer() {
    _hideScrollbarTimer?.cancel();
    _hideScrollbarTimer = Timer(const Duration(seconds: 4), () {
      setState(() => _isScrollbarVisible = false);
    });
  }

  void _onScreenTap() {
    setState(() => _isScrollbarVisible = true);
    _startHideScrollbarTimer();
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

          if (_isPortrait != portraitNow) {
            _isPortrait = portraitNow;
            fitPolicy = _calculateFitPolicy();
            _isOrientationChanging = true;
          }

          if (!_pdfReady) {
            return const Center(child: CircularProgressIndicator());
          }

          final pdfPath = _isPortrait ? _portraitPath! : _landscapePath!;

          return Stack(
            children: [
              PDFView(
                key: ValueKey('$pdfPath-$_pdfVersion'),
                filePath: pdfPath,
                swipeHorizontal: true,
                fitPolicy: fitPolicy,
                pageSnap: true,
                onViewCreated: (controller) {
                  _pdfController = controller;
                },
                onRender: (pages) async {
                  _totalPages = pages ?? 0;

                  //if orientation is changing
                  if (_isOrientationChanging) {
                    _currentPage = PageMapper.orientationMapper(_currentPage, _isPortrait);
                  }
                  await _pdfController?.setPage(_currentPage);

                  Future.delayed(const Duration(milliseconds: 200), () {
                    _isOrientationChanging = false;
                  });
                  print(
                      '[ONRENDER2] onrender current page is now $_currentPage');

                  setState(() {});
                },
                onPageChanged: (page, _) {
                  if (page == null) return;
                  if (_isOrientationChanging || _isPdfChanging) {
                    _isPdfChanging = false;
                    return;
                  };
                  print('[ONPAGECHANGE] current page is now $_currentPage');

                  setState(() => _currentPage = page);
                  StorageManager.saveCurrentPage(page);
                },
              ),

              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _onScreenTap,
                ),
              ),

              if (_isScrollbarVisible && _totalPages > 0)
                Positioned(
                  bottom: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Text(
                        '${MediaQuery
                            .of(context)
                            .orientation == Orientation.landscape
                            ? ((_totalPages - _currentPage) * 2 - 1)
                            : (_totalPages - _currentPage)}/${MediaQuery
                            .of(context)
                            .orientation == Orientation.landscape
                            ? (_totalPages * 2 - 1)
                            : _totalPages}',
                        style: const TextStyle(
                          color: Color(0xFF025C32),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          activeColor: const Color.fromARGB(255, 2, 92, 50),
                          thumbColor: const Color.fromARGB(255, 175, 132, 4),
                          inactiveColor: const Color(0xFFD9B44A),
                          value: _currentPage.toDouble(),
                          min: 0,
                          max: (_totalPages - 1).toDouble(),
                          onChanged: (v) {
                            final page = v.toInt();
                            _pdfController?.setPage(page);
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.bookmarks_rounded,
                            color: Color(0xFF025C32)),
                        onPressed: _showBookmarksModal,
                      ),
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
                          //Going into settings can change pdf so incrementing version causes rebuild of widget
                          //Change to correct values before rebuilding
                          _isPdfChanging = true;
                          await _loadPdfPaths();
                          fitPolicy = _calculateFitPolicy();
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

  // -------------------------
  // Bookmarks
  // -------------------------
  void _showBookmarksModal() {
    showModalBottomSheet(
      backgroundColor: const Color.fromARGB(255, 235, 243, 236),
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Bookmark button
                  Container(
                    margin: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: () {
                        _addBookmark();
                        setModalState(() {}); // refresh modal
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFBFBFB),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Bookmark This Page',
                        style: TextStyle(fontSize: 18, color: Color(
                            0xFF2A6767)),
                      ),
                    ),
                  ),
                  // Bookmark list
                  Expanded(
                    child: ListView.builder(
                      itemCount: _bookmarks.length,
                      itemBuilder: (context, i) {
                        final bookmark = _bookmarks[i];
                        return BookmarkWidget(
                          bookmark: bookmark,
                          onBookmarkToggled: (b) {
                            setState(() => _bookmarks.remove(b));
                            StorageManager.saveBookmarks(_bookmarks);
                            setModalState(() {}); // refresh modal
                          },
                          onPagePressed: (b) {
                            final pdfPage = PageMapper.bookmarkGoToMapper(
                              b.pageNumber,
                              _isPortrait,
                            );
                            print(
                                "[BOOKMARK LOAD] Current bookmark page to retrieve $pdfPage");
                            _pdfController?.setPage(pdfPage);
                            setState(() => _currentPage = pdfPage);
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
      },
    );
  }
}
