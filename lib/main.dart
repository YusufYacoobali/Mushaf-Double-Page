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

  int _totalPages = 0;     // PDF pages
  int _currentPdfPage = 0;

  bool _isPortrait = true;
  bool _isScrollbarVisible = true;
  Timer? _hideScrollbarTimer;

  bool isOptimizedPortrait = true;
  bool isOptimizedLandscape = false;

  bool _isRestoringPage = true;
  bool _pdfReady = false;

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
    _isRestoringPage = true;

    isOptimizedPortrait = await StorageManager.getOptimizedPortrait();
    isOptimizedLandscape = await StorageManager.getOptimizedLandscape();

    await _loadPdfPaths();
    await _loadBookmarks();
    await _loadCurrentPage();

    fitPolicy = _calculateFitPolicy();
    _startHideScrollbarTimer();

    setState(() => _pdfReady = true);
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
    _currentPdfPage = await StorageManager.getCurrentPage();
  }

  FitPolicy _calculateFitPolicy() {
    return (!_isPortrait && isOptimizedLandscape)
        ? FitPolicy.WIDTH
        : FitPolicy.BOTH;
  }

  int get totalDisplayPages => PageMapper.mushafPages;

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
            _isRestoringPage = true;
          }

          if (!_pdfReady) {
            return const Center(child: CircularProgressIndicator());
          }

          final pdfPath = _isPortrait ? _portraitPath! : _landscapePath!;
          final currentDisplayPage = PageMapper.displayFromPdf(
            _currentPdfPage,
            _isPortrait,
          );

          return Stack(
            children: [
              PDFView(
                key: ValueKey(pdfPath),
                filePath: pdfPath,
                swipeHorizontal: true,
                fitPolicy: fitPolicy,
                pageSnap: true,
                onViewCreated: (controller) {
                  _pdfController = controller;
                },
                onRender: (pages) async {
                  _totalPages = pages ?? 0;
                  _currentPdfPage = PageMapper.orientationMapper(_currentPdfPage, _isPortrait);

                  //if orientation is changing
                  if (_isRestoringPage) {
                    print('[ORIENTATION] changing Portait $_isPortrait');
                    await _pdfController?.setPage(_currentPdfPage);
                  }
                  print('[ORIENTATION] didnt count as changing $_isPortrait');
                  Future.delayed(const Duration(milliseconds: 200), () {
                    _isRestoringPage = false;
                  });
                  print('[ONRENDER2] onrender current page is now $_currentPdfPage');

                  setState(() {});
                },
                onPageChanged: (page, _) {
                  if (page == null) return;
                  if (_isRestoringPage) return;
                  print('[ONPAGECHANGE] current page is now $_currentPdfPage');

                  setState(() => _currentPdfPage = page);
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
                        '${MediaQuery.of(context).orientation == Orientation.landscape ? ((_totalPages - _currentPdfPage) * 2 - 1) : (_totalPages - _currentPdfPage)}/${MediaQuery.of(context).orientation == Orientation.landscape ? (_totalPages * 2 - 1) : _totalPages}',
                        style: const TextStyle(
                          color: Color(0xFF025C32),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          activeColor: const Color(0xFF025C32),
                          inactiveColor: const Color(0xFFD9B44A),
                          thumbColor:
                          const Color.fromARGB(255, 175, 132, 4),
                          value: _currentPdfPage.toDouble(),
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
                          print('[DEBUG] Settings tapped');
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const Settings()),
                          );
                          print('[DEBUG] Returned from Settings');
                          //await _initializeViewer(); // Reload settings after returning
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
      builder: (_) {
        return ListView.builder(
          itemCount: _bookmarks.length,
          itemBuilder: (context, i) {
            final bookmark = _bookmarks[i];
            return BookmarkWidget(
              bookmark: bookmark,
              onBookmarkToggled: (b) {
                setState(() => _bookmarks.remove(b));
                StorageManager.saveBookmarks(_bookmarks);
              },
              onPagePressed: (b) {
                final pdfPage = PageMapper.pdfFromDisplay(
                  b.pageNumber,
                  _isPortrait,
                );
                _pdfController?.setPage(pdfPage);
                setState(() => _currentPdfPage = pdfPage);
              },
            );
          },
        );
      },
    );
  }
}
