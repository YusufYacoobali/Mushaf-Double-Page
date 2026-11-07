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

  test('fully and meaningfully partially visible ayahs do not move', () {
    for (final rect in [
      const Rect.fromLTWH(20, 20, 100, 20),
      const Rect.fromLTWH(20, 85, 100, 30),
      const Rect.fromLTWH(20, -10, 100, 30),
    ]) {
      expect(geometry([rect]).visible, isTrue);
      expect(geometry([rect]).delta, 0);
    }
  });
  test('one visible line keeps the entire multi-rectangle ayah still', () {
    expect(
      geometry(const [
        Rect.fromLTWH(20, -70, 100, 20),
        Rect.fromLTWH(20, 40, 100, 20),
        Rect.fromLTWH(20, 150, 100, 20),
      ]).delta,
      0,
    );
  });
  test('reveals the nearest line with sixteen pixels of breathing room', () {
    expect(geometry(const [Rect.fromLTWH(20, 120, 100, 20)]).delta, 56);
    expect(geometry(const [Rect.fromLTWH(20, -50, 100, 20)]).delta, -66);
    expect(
      geometry(const [
        Rect.fromLTWH(20, -50, 100, 20),
        Rect.fromLTWH(20, 120, 100, 20),
      ]).delta,
      56,
    );
  });
  test(
    'edge slivers are not meaningful visibility and extents are clamped',
    () {
      expect(geometry(const [Rect.fromLTWH(20, 99, 100, 30)]).delta, 45);
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
      expect(surface.moves, [56]);
      for (var tick = 0; tick < 50; tick++) {
        expect(request(1), isNull);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(surface.moves, [56]);
    },
  );
  testWidgets(
    'rapid ayah changes replace stale work and invalidate active animations',
    (tester) async {
      follower.reveal(request(1)!);
      follower.reveal(request(2)!);
      await tester.pump();
      expect(surface.moves, [96]);
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
    expect(surface.moves, [56]);
    // Manual motion after consumption must not pull that same ayah back.
    follower.manualActivity();
    expect(request(1), isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(surface.moves, [56]);
  });
  testWidgets('navigation finishes before measuring the destination page', (
    tester,
  ) async {
    final gate = Completer<void>();
    final done = follower.revealAfterNavigation(request(1)!, gate.future);
    await tester.pump();
    expect(surface.moves, isEmpty);
    follower.configureView(layoutIdentity: 'portrait', visiblePages: [5]);
    follower.attach(5, surface);
    gate.complete();
    await done;
    await tester.pump();
    expect(surface.moves, [56]);
  });
  for (final reason in [
    'manual navigation',
    'rotation',
    'mushaf',
    'new selection',
  ]) {
    testWidgets('$reason rejects an old navigation completion', (tester) async {
      final gate = Completer<void>();
      final done = follower.revealAfterNavigation(request(1)!, gate.future);
      if (reason == 'new selection') {
        request(2, session: 2);
      } else if (reason == 'manual navigation') {
        follower.invalidate();
      } else {
        follower.configureView(layoutIdentity: reason, visiblePages: [4]);
      }
      gate.complete();
      await done;
      await tester.pump();
      expect(surface.moves, isEmpty);
    });
  }
  testWidgets(
    'a visible portion on the other spread page prevents all movement',
    (tester) async {
      follower.configureView(layoutIdentity: 'spread', visiblePages: [4, 5]);
      final visible = TestSurface();
      final other = AudioVerticalFollower(
        rectsFor: (p, s, a, m) => [
          Rect.fromLTWH(20, p == 5 ? 40 : 120, 100, 20),
        ],
      )..configureView(layoutIdentity: 'spread', visiblePages: [4, 5]);
      other.attach(4, surface);
      other.attach(5, visible);
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
      );
      await tester.pump();
      expect(surface.moves, isEmpty);
      expect(visible.moves, isEmpty);
      other.dispose();
    },
  );
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
