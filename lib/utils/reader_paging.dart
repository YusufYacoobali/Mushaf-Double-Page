import 'dart:async';

import 'package:flutter/foundation.dart';

import 'page_mapper.dart';
import 'reader_layout.dart';

enum PageTurnPhase { idle, dragging, settling }

/// Logical file-page navigation shared by the reader, turn host and audio
/// follower. [focusedPage] and [visiblePages] always describe the committed
/// view. A partially turned sheet has a separate [destinationIndex].
class ReaderPaging extends ChangeNotifier {
  ReaderPaging({required int initialPage, required this.lastPage})
    : _focusedPage = initialPage.clamp(1, lastPage);

  int lastPage;
  int _focusedPage;
  int get focusedPage => _focusedPage;
  ReaderPageMode _mode = ReaderPageMode.single;
  ReaderPageMode get mode => _mode;

  int _bookStart = 1;
  int _generation = 0, _operation = 0;
  int? _commandOperation;
  int get generation => _generation;
  int get operation => _operation;

  /// Recheck an awaited command before recording a visit. Resizing can settle
  /// that same command with a new visual operation number.
  bool isCurrentCommand(int token) => ready && _commandOperation == token;
  Object? _owner;
  bool _disposed = false;
  bool get ready => !_disposed && _owner != null && _generation != 0;

  PageTurnPhase _phase = PageTurnPhase.idle;
  PageTurnPhase get phase => _phase;
  bool get settled => ready && _phase == PageTurnPhase.idle;
  int? _pendingTarget, _destinationIndex;
  int? get pendingTarget => _pendingTarget;
  int? get destinationIndex => _destinationIndex;
  double _progress = 0;
  double get progress => _progress;
  bool _completing = false;
  bool get completing => _completing;
  Completer<bool>? _settlement;

  /// Resolves on either end of a manual turn or on reaching the requested
  /// command target. A superseded operation or detached reader resolves false.
  Future<bool> get whenSettled =>
      _settlement?.future ?? Future<bool>.value(settled);

  bool get singlePage => mode == ReaderPageMode.single;
  bool get book => mode == ReaderPageMode.dualScreenBook;
  int get index => indexFor(focusedPage);
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

  /// Physical position on the open spread. A blank boundary leaf has no file.
  int? pageAt(int index, {required bool left}) {
    if (index < 0 || index >= pageCount) return null;
    if (singlePage) return firstPageAt(index);
    final right = book ? firstPageAt(index) : index * 2;
    final page = right + (left ? 1 : 0);
    return page >= 1 && page <= lastPage ? page : null;
  }

  List<int> get visiblePages => pagesFor(focusedPage);
  List<int> pagesFor(int page) => [
    ?pageAt(indexFor(page), left: false),
    if (!singlePage) ?pageAt(indexFor(page), left: true),
  ];

  // Configuration and host lifecycle calls run during widget reconciliation.
  // The widgets already rebuild in that pass, so these calls are silent.
  void configure(ReaderPageMode next, {bool force = false, int? focusPage}) {
    if (_disposed ||
        (_generation != 0 && mode == next && !force && focusPage == null)) {
      return;
    }
    _focusedPage = (focusPage ?? _pendingTarget ?? focusedPage).clamp(
      1,
      lastPage,
    );
    if (next == ReaderPageMode.dualScreenBook) {
      _bookStart = focusedPage.isEven ? 0 : 1;
    }
    _mode = next;
    if (focusPage != null) _commandOperation = null;
    _invalidate(reached: focusPage == null);
  }

  /// Called for a change of reading geometry within the same mode, e.g. zoom.
  /// The book's existing left/right pairing survives a resize.
  void geometryChanged() {
    if (_disposed) return;
    _focusedPage = _pendingTarget ?? focusedPage;
    _invalidate(reached: true);
  }

  void _invalidate({required bool reached}) {
    _generation++;
    _operation++;
    _end(reached);
  }

  void attach(Object owner) {
    if (_disposed || identical(_owner, owner)) return;
    if (_owner != null) geometryChanged();
    _owner = owner;
  }

  void detach(Object owner) {
    if (_disposed || !identical(_owner, owner)) return;
    _owner = null;
    _commandOperation = null;
    _invalidate(reached: false);
  }

  bool focus(int page) {
    if (!settled || page == focusedPage || !visiblePages.contains(page)) {
      return false;
    }
    _focusedPage = page;
    _commandOperation = null;
    return true;
  }

  bool startDrag(int direction) {
    if (!settled || direction.abs() != 1) return false;
    final next = index + direction;
    if (next < 0 || next >= pageCount) return false;
    _commandOperation = null;
    _operation++;
    _phase = PageTurnPhase.dragging;
    _destinationIndex = next;
    _settlement = Completer<bool>();
    notifyListeners();
    return true;
  }

  void dragTo(double fraction) {
    if (_phase == PageTurnPhase.dragging) setProgress(operation, fraction);
  }

  void setProgress(int token, double fraction) {
    if (_disposed || token != operation || _phase == PageTurnPhase.idle) return;
    final value = fraction.clamp(0.0, 1.0);
    if (value == _progress) return;
    _progress = value;
    notifyListeners();
  }

  void settleDrag({required bool commit}) {
    if (_phase != PageTurnPhase.dragging) return;
    _completing = commit;
    _phase = PageTurnPhase.settling;
    notifyListeners();
  }

  /// The host calls this once its animation reaches the requested endpoint.
  /// Only a true return transfers manual visit/persistence ownership to it.
  bool completeTurn(int token) {
    if (_disposed || token != operation || _phase != PageTurnPhase.settling) {
      return false;
    }
    final manualCommit = _completing && _pendingTarget == null;
    if (_completing) {
      _focusedPage =
          _pendingTarget ?? firstPageAt(_destinationIndex!).clamp(1, lastPage);
    }
    _end(true);
    notifyListeners();
    return manualCommit;
  }

  /// Abandons an uncommitted drag. If an explicit command was already issued,
  /// its logical target wins over the interrupted animation.
  void cancelTurn({bool notify = true}) {
    if (_disposed || _phase == PageTurnPhase.idle) return;
    _operation++;
    _focusedPage = _pendingTarget ?? focusedPage;
    _end(true);
    if (notify) notifyListeners();
  }

  /// Adjacent commands may animate. Same-spread, distant and explicit jump
  /// commands commit directly. Programmatic commits belong to the caller.
  Future<bool> goTo(int page, {bool animate = false}) {
    if (_disposed) return Future<bool>.value(false);
    final target = page.clamp(1, lastPage);
    if (animate && _pendingTarget == target) return _settlement!.future;
    final next = indexFor(target);
    final previousProgress = _pendingTarget != null && _destinationIndex == next
        ? progress
        : 0.0;
    _commandOperation = ++_operation;
    _end(false);
    if (!ready || !animate || (next - index).abs() != 1) {
      _focusedPage = target;
      final reached = ready;
      notifyListeners();
      return Future<bool>.value(reached);
    }

    _pendingTarget = target;
    _destinationIndex = next;
    _progress = previousProgress;
    _phase = PageTurnPhase.settling;
    _completing = true;
    final completion = _settlement = Completer<bool>();
    notifyListeners();
    return completion.future;
  }

  void _end(bool reached) {
    _phase = PageTurnPhase.idle;
    _destinationIndex = null;
    _pendingTarget = null;
    _progress = 0;
    _completing = false;
    _settlement?.complete(reached);
    _settlement = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _owner = null;
    _invalidate(reached: false);
    super.dispose();
  }
}
