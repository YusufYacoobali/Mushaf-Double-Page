import 'package:flutter/material.dart';
import 'page_mapper.dart';
import 'reader_layout.dart';

/// Holds the actual focused file page, independent of the PageView index.
/// A layout transition replaces the native controller but is not a page visit.
class ReaderPaging {
  ReaderPaging({required int initialPage, required this.lastPage})
    : focusedPage = initialPage.clamp(1, lastPage);
  int lastPage;
  int focusedPage;
  ReaderPageMode mode = ReaderPageMode.single;
  PageController? _controller;
  int generation = 0;
  int? _index;
  int? _commandTarget;
  bool _disposed = false;
  final _retired = <PageController>{};
  PageController get controller => _controller!;
  bool get singlePage => mode == ReaderPageMode.single;
  bool get book => mode == ReaderPageMode.dualScreenBook;
  int _bookStart = 1;
  int get pageCount => book
      ? (lastPage - _bookStart) ~/ 2 + 1
      : singlePage
      ? lastPage
      : lastPage ~/ 2 + 1;
  int indexFor(int page) => book
      ? (page - _bookStart) ~/ 2
      : PageMapper.pageIndexFromLogical(page, singlePage);
  int firstPageAt(int index) => book
      ? _bookStart + index * 2
      : PageMapper.logicalFromPageIndex(index, singlePage);
  List<int> get visiblePages => pagesFor(focusedPage);
  List<int> pagesFor(int page) => book
      ? [
          for (
            var p = firstPageAt(indexFor(page));
            p < firstPageAt(indexFor(page)) + 2;
            p++
          )
            if (p >= 1 && p <= lastPage) p,
        ]
      : PageMapper.visiblePages(page, singlePage, lastPage);

  void configure(ReaderPageMode next, {bool force = false}) {
    if (_controller != null && mode == next && !force) return;
    // Enter with the exact focused page on the left, even when it is odd.
    // Keep that pairing stable while navigating/focusing either screen.
    if (next == ReaderPageMode.dualScreenBook && (mode != next || force)) {
      _bookStart = focusedPage.isEven ? 0 : 1;
    }
    mode = next;
    _commandTarget = null;
    final old = _controller;
    _index = indexFor(focusedPage);
    _controller = PageController(initialPage: _index!, keepPage: false);
    generation++;
    if (old != null) {
      _retired.add(old);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_retired.remove(old)) old.dispose();
      });
    }
  }

  bool changed(int index, int callbackGeneration) {
    if (_disposed ||
        callbackGeneration != generation ||
        index == _index ||
        _commandTarget != null) {
      return false;
    }
    _index = index;
    focusedPage = firstPageAt(index).clamp(1, lastPage);
    return true;
  }

  bool focus(int page) {
    if (_disposed || page == focusedPage || !visiblePages.contains(page)) {
      return false;
    }
    focusedPage = page;
    return true;
  }

  Future<void> goTo(int page, {bool animate = false}) async {
    if (_disposed) return;
    focusedPage = page.clamp(1, lastPage);
    final target = indexFor(focusedPage);
    _index = target;
    final native = _controller;
    if (native == null || !native.hasClients) return;
    final commandGeneration = generation;
    _commandTarget = target;
    try {
      if (animate) {
        await native.animateToPage(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } else {
        native.jumpToPage(target);
      }
    } finally {
      if (generation == commandGeneration) _commandTarget = null;
    }
  }

  void dispose() {
    _disposed = true;
    _controller?.dispose();
    for (final controller in _retired) {
      controller.dispose();
    }
    _retired.clear();
  }
}
