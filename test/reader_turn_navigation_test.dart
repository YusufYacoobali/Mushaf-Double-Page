import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/reader_layout.dart';
import 'package:mushaf_two_page/utils/reader_paging.dart';

void main() {
  ReaderPaging reader(int page, ReaderPageMode mode, {int last = 20}) {
    final paging = ReaderPaging(initialPage: page, lastPage: last)
      ..configure(mode)
      ..attach(Object());
    addTearDown(paging.dispose);
    return paging;
  }

  test('ordinary and book leaf slots include their own blank boundaries', () {
    final spread = reader(4, ReaderPageMode.spread);
    List<int?> leaves(ReaderPaging p, int index) => [
      p.pageAt(index, left: false),
      p.pageAt(index, left: true),
    ];
    expect(leaves(spread, 0), [null, 1]);
    expect(leaves(spread, spread.index), [4, 5]);
    expect(leaves(spread, spread.index + 1), [6, 7]);
    expect(leaves(spread, spread.pageCount - 1), [20, null]);
    final oddBook = reader(5, ReaderPageMode.dualScreenBook, last: 9);
    expect(leaves(oddBook, 0), [1, 2]);
    expect(leaves(oddBook, oddBook.index), [5, 6]);
    expect(leaves(oddBook, oddBook.index + 1), [7, 8]);
    expect(leaves(oddBook, oddBook.pageCount - 1), [9, null]);
    final evenBook = reader(4, ReaderPageMode.dualScreenBook, last: 9);
    expect(leaves(evenBook, 0), [null, 1]);
    expect(leaves(evenBook, evenBook.index), [4, 5]);
    expect(leaves(evenBook, evenBook.pageCount - 1), [8, 9]);
  });

  test(
    'returning a drag commits nothing; a completed turn commits once',
    () async {
      final p = reader(4, ReaderPageMode.spread);
      expect(p.startDrag(1), isTrue);
      expect(p.startDrag(-1), isFalse);
      final cancelled = p.whenSettled;
      final token = p.operation;
      p.dragTo(.23);
      expect(p.visiblePages, [4, 5]);
      expect(p.pendingTarget, isNull);
      expect(p.destinationIndex, 3);
      expect(p.focus(5), isFalse);
      expect(p.settled, isFalse);
      p.settleDrag(commit: false);
      expect(p.completing, isFalse);
      expect(p.startDrag(1), isFalse);
      expect(p.completeTurn(token), isFalse);
      expect(await cancelled, isTrue);
      expect(p.focusedPage, 4);
      expect(p.settled, isTrue);

      expect(p.startDrag(1), isTrue);
      p.settleDrag(commit: true);
      p.setProgress(token, .8);
      expect(p.progress, 0);
      expect(p.completeTurn(token), isFalse);
      expect(p.completeTurn(p.operation), isTrue);
      expect(p.completeTurn(p.operation), isFalse);
      expect(p.focusedPage, 6);
      expect(p.visiblePages, [6, 7]);
    },
  );

  test(
    'a command settles on the exact leaf and never dispatches a manual visit',
    () async {
      final p = reader(4, ReaderPageMode.spread);
      final first = p.goTo(6, animate: true);
      expect(p.goTo(6, animate: true), same(first));
      expect(p.phase, PageTurnPhase.settling);
      expect(p.focusedPage, 4);
      expect(p.pendingTarget, 6);
      final token = p.operation;
      p.setProgress(token, .43);

      final latest = p.goTo(7, animate: true);
      expect(await first, isFalse);
      expect(p.focusedPage, 4);
      expect(p.pendingTarget, 7);
      expect(p.progress, .43);
      expect(p.completeTurn(token), isFalse);
      expect(p.completeTurn(p.operation), isFalse);
      expect(await latest, isTrue);
      expect(p.focusedPage, 7);
      expect(p.pendingTarget, isNull);
      expect(p.settled, isTrue);

      expect(await p.goTo(6, animate: true), isTrue);
      expect(p.focusedPage, 6);
      expect(p.phase, PageTurnPhase.idle);
    },
  );

  test(
    'direct and distant targets supersede manual and automatic work',
    () async {
      final p = reader(7, ReaderPageMode.single);
      p.startDrag(-1);
      final drag = p.whenSettled;
      final staleDrag = p.operation;
      expect(await p.goTo(19, animate: true), isTrue);
      expect(await drag, isFalse);
      expect(p.completeTurn(staleDrag), isFalse);
      expect(p.focusedPage, 19);
      final command = p.goTo(18, animate: true);
      final staleCommand = p.operation;
      expect(await p.goTo(18), isTrue);
      expect(await command, isFalse);
      expect(p.completeTurn(staleCommand), isFalse);
      expect(p.focusedPage, 18);
      await p.goTo(20);
      expect(p.startDrag(1), isFalse);
      await p.goTo(1);
      expect(p.startDrag(-1), isFalse);
    },
  );

  test(
    'posture changes preserve committed manual focus or latest explicit target',
    () async {
      final p = reader(5, ReaderPageMode.spread);
      p.startDrag(-1);
      final manual = p.operation;
      p.configure(ReaderPageMode.single);
      expect(p.completeTurn(manual), isFalse);
      expect(p.focusedPage, 5);
      final command = p.goTo(6, animate: true);
      final token = p.operation;
      final generation = p.generation;
      p.configure(ReaderPageMode.dualScreenBook);
      expect(p.generation, greaterThan(generation));
      expect(p.completeTurn(token), isFalse);
      expect(await command, isTrue);
      expect(p.isCurrentCommand(token), isTrue);
      expect(p.focusedPage, 6);
      expect(p.visiblePages, [6, 7]);

      final resize = p.goTo(9, animate: true);
      expect(p.isCurrentCommand(token), isFalse);
      final resizedCommand = p.operation;
      p.geometryChanged();
      expect(await resize, isTrue);
      expect(p.isCurrentCommand(resizedCommand), isTrue);
      expect(p.focusedPage, 9);
      expect(p.visiblePages, [8, 9]);
    },
  );

  test(
    'rechecking a settled command discards visits superseded before await',
    () async {
      final p = reader(4, ReaderPageMode.spread);
      final first = p.goTo(7);
      final old = p.operation;
      final latest = p.goTo(7);
      final current = p.operation;
      expect(await first, isTrue);
      expect(p.isCurrentCommand(old), isFalse);
      expect(await latest, isTrue);
      expect(p.isCurrentCommand(current), isTrue);
      expect(p.focus(6), isTrue);
      expect(p.isCurrentCommand(current), isFalse);
      await p.goTo(7);
      final beforeDrag = p.operation;
      expect(p.startDrag(1), isTrue);
      expect(p.isCurrentCommand(beforeDrag), isFalse);
    },
  );

  test(
    'changing edition supersedes the old command with the converted focus',
    () async {
      final p = reader(18, ReaderPageMode.single);
      final stale = p.goTo(19, animate: true);
      p.lastPage = 10;
      p.configure(p.mode, force: true, focusPage: 8);
      expect(await stale, isFalse);
      expect(p.focusedPage, 8);
      expect(p.settled, isTrue);
    },
  );

  test(
    'host retirement and disposal reject late completion and release waiters',
    () async {
      final p = ReaderPaging(initialPage: 3, lastPage: 20)
        ..configure(ReaderPageMode.single);
      final a = Object(), b = Object();
      expect(p.ready, isFalse);
      p.attach(a);
      final retired = p.goTo(4, animate: true);
      final old = p.operation;
      p.detach(a);
      expect(await retired, isFalse);
      expect(p.ready, isFalse);
      p.attach(b);
      p.detach(a);
      expect(p.ready, isTrue);
      expect(p.completeTurn(old), isFalse);
      final outstanding = p.goTo(4, animate: true);
      p.dispose();
      expect(await outstanding, isFalse);
      expect(await p.whenSettled, isFalse);
      expect(p.completeTurn(p.operation), isFalse);
      expect(p.startDrag(-1), isFalse);
    },
  );
}
