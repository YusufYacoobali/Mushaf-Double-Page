import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mushaf_two_page/pages/settings.dart';
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
  PdfController? _pdfController;

  int _totalPages = 0;
  int _currentPage = 0;
  int _pdfVersion = 0;

  bool _isScrollbarVisible = true;
  Timer? _hideScrollbarTimer;

  bool _isPortrait = true;
  bool isOptimizedPortrait = true;
  bool isOptimizedLandscape = false;

  bool _isPdfChanging = false;
  bool _isOrientationChanging = false;
  bool _pdfReady = false;

  String? _portraitPath;
  String? _landscapePath;

  final List<Bookmark> _bookmarks = [];

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

    _startHideScrollbarTimer();
    await _loadPdf();

    setState(() => _pdfReady = true);
  }

  Future<void> _loadPdf() async {
    final path = _isPortrait ? _portraitPath! : _landscapePath!;

    final documentFuture = PdfDocument.openFile(path);

    final doc = await documentFuture;
    _totalPages = doc.pagesCount;

    if (_isOrientationChanging) {
      _currentPage =
          PageMapper.orientationMapper(_currentPage, _isPortrait);
    }

    _pdfController?.dispose();
    _pdfController = PdfController(
      document: PdfDocument.openFile(path),
      initialPage: _currentPage,
    );

    _isOrientationChanging = false;
    setState(() {});
  }

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

  Future<void> _loadCurrentPage() async {
    _currentPage = await StorageManager.getCurrentPage();
  }

  void _startHideScrollbarTimer() {
    _hideScrollbarTimer?.cancel();
    _hideScrollbarTimer = Timer(const Duration(seconds: 6), () {
      setState(() => _isScrollbarVisible = false);
    });
  }

  void _onScreenTap() {
    setState(() => _isScrollbarVisible = true);
    _startHideScrollbarTimer();
  }

  void _addBookmark() {
    final pageNumber =
    PageMapper.bookmarkAddMapper(_currentPage, _isPortrait);

    if (_bookmarks.any((b) => b.pageNumber == pageNumber)) return;

    setState(() => _bookmarks.add(Bookmark(pageNumber: pageNumber)));
    StorageManager.saveBookmarks(_bookmarks);
  }

  @override
  void dispose() {
    _hideScrollbarTimer?.cancel();
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OrientationBuilder(
        builder: (context, orientation) {
          final portraitNow = orientation == Orientation.portrait;

          if (_isPortrait != portraitNow) {
            _isPortrait = portraitNow;
            _isOrientationChanging = true;
            _loadPdf();
          }

          if (!_pdfReady || _pdfController == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            children: [
              PdfView(
                key: ValueKey('pdf-$_pdfVersion'),
                controller: _pdfController!,
                scrollDirection: Axis.horizontal,
                pageSnapping: true,
                onPageChanged: (page) {
                  if (_isPdfChanging || _isOrientationChanging) return;

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
                        '${_totalPages - _currentPage}/${_totalPages}',
                        style: const TextStyle(
                          color: Color(0xFF025C32),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _currentPage.toDouble(),
                          min: 0,
                          max: (_totalPages - 1).toDouble(),
                          onChanged: (v) {
                            final page = v.toInt();
                            _pdfController!.jumpToPage(page);
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.bookmarks_rounded,
                            color: Color(0xFF025C32)),
                        onPressed: _showBookmarksModal,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings,
                            color: Color(0xFF025C32)),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const Settings()),
                          );

                          _isPdfChanging = true;
                          await _loadPdfPaths();
                          _pdfVersion++;
                          await _loadPdf();
                          _isPdfChanging = false;
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

        return SafeArea(
          child: Container(
            height: isLandscape ? screenHeight * 0.85 : screenHeight * 0.65,
            decoration: const BoxDecoration(
              color: Color.fromARGB(255, 235, 243, 236),
              borderRadius:
              BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: ListView.builder(
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
                    final pdfPage =
                    PageMapper.bookmarkGoToMapper(
                        b.pageNumber, _isPortrait);
                    _pdfController!.jumpToPage(pdfPage);
                    setState(() => _currentPage = pdfPage);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
