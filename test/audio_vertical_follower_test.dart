import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/audio_vertical_follower.dart';

class TestSurface implements AudioVerticalSurface {
  final moves = <double>[];
  bool Function()? valid;
  @override
  AudioVerticalGeometry measure(List<Rect> rects) => AudioVerticalGeometry(
    viewport: const Rect.fromLTWH(0, 0, 200, 100),
    rects: rects,
    minDelta: -500,
    maxDelta: 500,
  );
  @override
  void moveBy(double delta, bool Function() valid) {
    moves.add(delta);
    this.valid = valid;
  }

  @override
  void cancel() {}
}

void main() {
  AudioVerticalGeometry geometry(
    List<Rect> rects, {
    double min = -500,
    double max = 500,
  }) => AudioVerticalGeometry(
    viewport: const Rect.fromLTWH(0, 0, 200, 100),
    rects: rects,
    minDelta: min,
    maxDelta: max,
  );

  test('fully visible ayahs keep their position and near-full spans fit', () {
    for (final rect in [
      const Rect.fromLTWH(20, 20, 100, 20),
      const Rect.fromLTWH(20, 4, 100, 92),
      const Rect.fromLTWH(20, 0, 100, 100),
    ]) {
      expect(geometry([rect]).visible, isTrue);
      expect(geometry([rect]).delta, 0);
    }
  });
  test('partially visible lines are brought fully into the reading area', () {
    for (final (rect, movement) in [
      (const Rect.fromLTWH(20, 85, 100, 30), 50.0),
      (const Rect.fromLTWH(20, -10, 100, 30), -45.0),
    ]) {
      final measured = geometry([rect]);
      expect(measured.visible, isFalse);
      expect(measured.delta, movement);
      expect(
        geometry([rect.shift(Offset(0, -measured.delta))]).visible,
        isTrue,
      );
    }
  });
  test('a visible middle line cannot suppress the rest of a fitting ayah', () {
    for (final rects in [
      const [
        Rect.fromLTWH(20, -15, 100, 20),
        Rect.fromLTWH(20, 15, 100, 10),
        Rect.fromLTWH(20, 45, 100, 10),
      ],
      const [
        Rect.fromLTWH(20, 55, 100, 10),
        Rect.fromLTWH(20, 75, 100, 10),
        Rect.fromLTWH(20, 95, 100, 10),
      ],
    ]) {
      final measured = geometry(rects);
      expect(measured.visible, isFalse);
      expect(measured.delta, isNot(0));
      final revealed = rects
          .map((rect) => rect.shift(Offset(0, -measured.delta)))
          .toList();
      expect(geometry(revealed).visible, isTrue);
      expect(geometry(revealed).delta, 0);
    }
  });
  test('one movement centres all lines of an off-screen ayah that fits', () {
    final rects = const [
      Rect.fromLTWH(20, 120, 100, 20),
      Rect.fromLTWH(20, 145, 100, 20),
      Rect.fromLTWH(20, 170, 100, 20),
    ];
    final movement = geometry(rects).delta;
    expect(movement, 105);
    expect(
      geometry(
        rects.map((rect) => rect.shift(Offset(0, -movement))).toList(),
      ).visible,
      isTrue,
    );
  });
  test(
    'oversized ayahs start with their first line rather than the nearest',
    () {
      // Deliberately unordered: the reading start comes from geometry, not the
      // rectangle nearest the viewport or the first metadata entry.
      final rects = const [
        Rect.fromLTWH(20, 150, 100, 20),
        Rect.fromLTWH(20, 40, 100, 20),
        Rect.fromLTWH(20, -70, 100, 20),
      ];
      final movement = geometry(rects).delta;
      expect(movement, -86);
      final revealed = rects
          .map((rect) => rect.shift(Offset(0, -movement)))
          .toList();
      expect(revealed.last.top, 16);
      expect(revealed.last.bottom, 36);
      expect(geometry(revealed).visible, isTrue);
      expect(geometry(revealed).delta, 0);
    },
  );
  test(
    'edge slivers are revealed and unavailable scroll extents are respected',
    () {
      expect(geometry(const [Rect.fromLTWH(20, 99, 100, 30)]).delta, 64);
      expect(
        geometry(const [Rect.fromLTWH(20, 120, 100, 20)], max: 25).delta,
        25,
      );
      expect(
        geometry(const [Rect.fromLTWH(20, -50, 100, 20)], min: -20).delta,
        -20,
      );
      expect(
        geometry(const [Rect.fromLTWH(20, 120, 100, 20)], min: 0, max: 0).delta,
        0,
      );
    },
  );
  test(
    'horizontal-only obstruction and empty metadata cannot trigger vertical motion',
    () {
      expect(geometry(const [Rect.fromLTWH(300, 120, 100, 20)]).delta, 0);
      expect(geometry(const []).delta, 0);
    },
  );

  late AudioVerticalFollower follower;
  late TestSurface surface;
  setUp(() {
    follower = AudioVerticalFollower(
      rectsFor: (page, surah, ayah, mushaf) => [
        Rect.fromLTWH(20, ayah == 1 ? 120 : 160, 100, 20),
      ],
    );
    follower.configureView(layoutIdentity: 'portrait', visiblePages: [4]);
    surface = TestSurface();
    follower.attach(4, surface);
  });
  tearDown(() => follower.dispose());
  AudioVerticalRequest? request(
    int ayah, {
    bool visible = true,
    int session = 1,
  }) => follower.beginAyah(
    playing: true,
    visible: visible,
    session: session,
    cycle: 1,
    surah: 2,
    ayah: ayah,
    mushaf: 'madani',
  );

  testWidgets(
    'position ticks and repeated layout frames cannot enqueue another reveal',
    (tester) async {
      follower.reveal(request(1)!);
      await tester.pump();
      expect(surface.moves, [80]);
      for (var tick = 0; tick < 50; tick++) {
        expect(request(1), isNull);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(surface.moves, [80]);
    },
  );
  testWidgets(
    'rapid ayah changes replace stale work and invalidate active animations',
    (tester) async {
      follower.reveal(request(1)!);
      follower.reveal(request(2)!);
      await tester.pump();
      expect(surface.moves, [120]);
      expect(surface.valid!(), isTrue);
      follower.invalidate();
      expect(surface.valid!(), isFalse);
    },
  );
  testWidgets('gestures suspend a new ayah until the idle period ends', (
    tester,
  ) async {
    follower.pointerDown(10);
    follower.reveal(request(1)!);
    await tester.pump(const Duration(seconds: 1));
    expect(surface.moves, isEmpty);
    follower.pointerUp(10);
    await tester.pump(const Duration(milliseconds: 600));
    expect(surface.moves, isEmpty);
    await tester.pump(const Duration(milliseconds: 51));
    await tester.pump();
    expect(surface.moves, [80]);
    // Manual motion after consumption must not pull that same ayah back.
    follower.manualActivity();
    expect(request(1), isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(surface.moves, [80]);
  });
  testWidgets('navigation finishes before measuring the destination page', (
    tester,
  ) async {
    final gate = Completer<bool>();
    final done = follower.revealAfterNavigation(
      request(1)!,
      gate.future,
      preferredPage: 5,
    );
    await tester.pump();
    expect(surface.moves, isEmpty);
    follower.configureView(layoutIdentity: 'portrait', visiblePages: [5]);
    follower.attach(5, surface);
    gate.complete(true);
    await done;
    await tester.pump();
    expect(surface.moves, [80]);
  });
  testWidgets('a superseded command cannot focus or reveal after settlement', (
    tester,
  ) async {
    var committed = 0;
    final first = request(1)!;
    await follower.revealAfterNavigation(
      first,
      Future.value(false),
      onSettled: () => committed++,
    );
    final second = request(2)!;
    var operation = 1;
    final settled = follower.revealAfterNavigation(
      second,
      Future.value(true),
      currentNavigation: () => operation == 1,
      onSettled: () => committed++,
    );
    operation++; // A newer command arrived before the completion microtask.
    await settled;
    await tester.pump();
    expect(committed, 0);
    expect(surface.moves, isEmpty);
  });
  for (final reason in [
    'manual navigation',
    'rotation',
    'mushaf',
    'new selection',
  ]) {
    testWidgets('$reason rejects an old navigation completion', (tester) async {
      final gate = Completer<bool>();
      final done = follower.revealAfterNavigation(request(1)!, gate.future);
      if (reason == 'new selection') {
        request(2, session: 2);
      } else if (reason == 'manual navigation') {
        follower.invalidate();
      } else {
        follower.configureView(layoutIdentity: reason, visiblePages: [4]);
      }
      gate.complete(true);
      await done;
      await tester.pump();
      expect(surface.moves, isEmpty);
    });
  }
  testWidgets(
    'the preferred page is revealed even when the other spread leaf is visible',
    (tester) async {
      for (final preferredPage in [4, 5]) {
        final chosen = TestSurface(), visible = TestSurface();
        final other = AudioVerticalFollower(
          rectsFor: (p, s, a, m) => [
            Rect.fromLTWH(20, p == preferredPage ? 120 : 40, 100, 20),
          ],
        )..configureView(layoutIdentity: 'spread', visiblePages: [4, 5]);
        other.attach(preferredPage, chosen);
        other.attach(preferredPage == 4 ? 5 : 4, visible);
        other.reveal(
          other.beginAyah(
            playing: true,
            visible: true,
            session: 1,
            cycle: 1,
            surah: 2,
            ayah: 1,
            mushaf: 'madani',
          )!,
          preferredPage: preferredPage,
        );
        await tester.pump();
        expect(chosen.moves, [80]);
        expect(visible.moves, isEmpty);
        other.dispose();
      }
    },
  );
  testWidgets('a missing preferred page cannot move a different leaf', (
    tester,
  ) async {
    follower.reveal(request(1)!, preferredPage: 5);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump();
    }
    expect(surface.moves, isEmpty);
  });
  testWidgets(
    'covered readers discard pending work without a catch-up reveal',
    (tester) async {
      var showing = true;
      final guarded = AudioVerticalFollower(
        canFollow: () => showing,
        rectsFor: (p, s, a, m) => const [Rect.fromLTWH(20, 120, 100, 20)],
      )..configureView(layoutIdentity: 'portrait', visiblePages: [4]);
      guarded.attach(4, surface);
      final request = guarded.beginAyah(
        playing: true,
        visible: true,
        session: 1,
        cycle: 1,
        surah: 2,
        ayah: 1,
        mushaf: 'madani',
      )!;
      guarded.reveal(request);
      showing = false;
      await tester.pump();
      showing = true;
      await tester.pump();
      expect(surface.moves, isEmpty);
      expect(
        guarded.beginAyah(
          playing: true,
          visible: true,
          session: 1,
          cycle: 1,
          surah: 2,
          ayah: 1,
          mushaf: 'madani',
        ),
        isNull,
      );
      guarded.dispose();
    },
  );
}
