import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/components/quran_page_turn_painter.dart';

const _size = Size(220, 168);
const _left = Rect.fromLTWH(4, 20, 104, 128);
const _right = Rect.fromLTWH(112, 20, 104, 128);
const _clips = [Rect.fromLTWH(0, 0, 109, 168), Rect.fromLTWH(111, 0, 109, 168)];
const _background = Color(0xff343434);
const _red = Color(0xffff0000);
const _green = Color(0xff00ff00);
const _blue = Color(0xff0000ff);
const _orange = Color(0xffff7700);
const _pink = Color(0xffff00ff);
const _cyan = Color(0xff00ffff);
const _paper = Color(0xff50483e);
const _lightPaper = Color(0xfffaf8f0);

Future<ui.Image> _page(int number, Color fill, {bool marked = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 104, 128), Paint()..color = fill);
  if (marked) {
    canvas.drawRect(const Rect.fromLTWH(0, 0, 26, 128), Paint()..color = _pink);
    canvas.drawRect(
      const Rect.fromLTWH(78, 0, 26, 128),
      Paint()..color = _cyan,
    );
  }
  final label = TextPainter(
    text: TextSpan(
      text: '$number',
      style: const TextStyle(color: Colors.white, fontSize: 20),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  label.paint(canvas, const Offset(9, 26));
  label.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(104, 128);
  picture.dispose();
  return image;
}

class _Pixels {
  _Pixels(this.bytes);
  final ByteData bytes;

  (int, int, int) at(int x, int y) {
    final at = 4 * (y * _size.width.toInt() + x);
    return (bytes.getUint8(at), bytes.getUint8(at + 1), bytes.getUint8(at + 2));
  }
}

Future<_Pixels> _frame(
  List<PageTurnLeaf> source,
  List<PageTurnLeaf> destination,
  double progress, {
  bool forward = true,
  List<Rect> clips = _clips,
  Color paperColor = _paper,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & _size, Paint()..color = _background);
  QuranPageTurnPainter(
    source: source,
    destination: destination,
    forward: forward,
    progress: progress,
    clipRegions: clips,
    paperColor: paperColor,
  ).paint(canvas, _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return _Pixels(pixels!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<PageTurnLeaf> current, next;
  setUpAll(() async {
    current = [
      PageTurnLeaf(bounds: _left, image: await _page(7, _orange, marked: true)),
      PageTurnLeaf(bounds: _right, image: await _page(6, _red)),
    ];
    next = [
      PageTurnLeaf(bounds: _left, image: await _page(9, _green)),
      PageTurnLeaf(bounds: _right, image: await _page(8, _blue, marked: true)),
    ];
  });
  tearDownAll(() {
    for (final leaf in [...current, ...next]) {
      leaf.image!.dispose();
    }
  });

  for (final forward in [true, false]) {
    test(
      'RTL spread faces, shading and hinge at 25%, 50% and 75% forward=$forward',
      () async {
        final source = forward ? current : next;
        final destination = forward ? next : current;
        final rest = await _frame(source, destination, 0, forward: forward);
        final mid = <_Pixels>[];
        for (final progress in [.25, .5, .75]) {
          final image = await _frame(
            source,
            destination,
            progress,
            forward: forward,
          );
          mid.add(image);
          expect(image.at(110, 80), (
            52,
            52,
            52,
          ), reason: 'Hinge must stay clear at $progress');
          expect(
            image.at(forward ? 205 : 14, 115),
            rest.at(forward ? 205 : 14, 115),
            reason:
                'The original opposite page stays stationary until the free edge covers it',
          );
          expect(
            image.at(forward ? 10 : 210, 96),
            forward ? (0, 255, 0) : (255, 0, 0),
            reason:
                'Uncovered paper must be the physical destination leaf underneath the turn',
          );
        }
        // The bent paper rises above the two flat page rectangles. A slightly
        // darkened strip on the exposed paper comes from the shadow of its edge.
        expect(
          [
            for (var x = 4; x < 216; x++) mid.first.at(x, 18),
          ].any((rgb) => rgb.$3 > 100 || rgb.$1 > 100),
          isTrue,
        );
        final revealed = [
          for (var x = forward ? 4 : 112; x < (forward ? 108 : 216); x++)
            mid.first.at(x, 96),
        ];
        expect(
          revealed.any(
            (rgb) => forward
                ? rgb.$1 == 0 && rgb.$3 == 0 && rgb.$2 > 150 && rgb.$2 < 253
                : rgb.$2 == 0 && rgb.$3 == 0 && rgb.$1 > 150 && rgb.$1 < 253,
          ),
          isTrue,
        );

        // Both numbered fixtures have a pink stripe on the left and cyan on the
        // right. Read their order from actual pixels, including on the back.
        for (final (frame, leftHalf) in [
          (mid.first, forward),
          (mid.last, !forward),
        ]) {
          final samples = [
            for (var x = leftHalf ? 4 : 112; x < (leftHalf ? 108 : 216); x++)
              frame.at(x, 96),
          ];
          final pink = samples.indexWhere(
            (p) => p.$1 > 140 && p.$2 < 10 && p.$3 > 140,
          );
          final cyan = samples.indexWhere(
            (p) => p.$1 < 10 && p.$2 > 140 && p.$3 > 140,
          );
          expect(pink, greaterThanOrEqualTo(0));
          expect(
            cyan,
            greaterThan(pink),
            reason: 'Quran text on either visible face must remain readable',
          );
        }
        final end = await _frame(source, destination, 1, forward: forward);
        final actualDestination = await _frame(destination, source, 0);
        expect(
          end.bytes.buffer.asUint8List(),
          actualDestination.bytes.buffer.asUint8List(),
        );
      },
    );
  }

  test(
    'single-page curl keeps its printed front and opaque blank reverse',
    () async {
      for (final (paper, paperRgb) in [
        (_paper, (80, 72, 62)),
        (_lightPaper, (250, 248, 240)),
      ]) {
        for (final forward in [true, false]) {
          final from = [PageTurnLeaf(bounds: _left, image: current[1].image)];
          final to = [PageTurnLeaf(bounds: _left, image: next[1].image)];
          for (final progress in [.25, .5, .75]) {
            final pixels = await _frame(
              from,
              to,
              progress,
              forward: forward,
              paperColor: paper,
            );
            final row = [for (var x = 4; x < 108; x++) pixels.at(x, 97)];
            expect(
              row.where((p) => p == paperRgb),
              isNotEmpty,
              reason: 'The reverse must be opaque blank paper at $progress',
            );
            expect(
              row[forward ? 0 : row.length - 1],
              forward ? (255, 0, 255) : (0, 255, 255),
              reason: 'The destination underneath retains its own orientation',
            );
            if (progress == .25) {
              expect(
                pixels.at(forward ? 48 : 64, 97),
                paperRgb,
                reason: 'The raised reverse has no incoming page markings',
              );
              expect(
                pixels.at(forward ? 92 : 20, 97),
                (255, 0, 0),
                reason:
                    'The outgoing printed face remains visible while curling',
              );
            }
            if (progress == .5) {
              expect(
                pixels.at(forward ? 97 : 14, 97),
                paperRgb,
                reason: 'The reverse stays blank as the curl crosses the page',
              );
              final abovePage = [
                for (var x = 4; x < 108; x++) pixels.at(x, 19),
              ];
              expect(
                abovePage.any((rgb) => rgb.$1 > rgb.$2 && rgb.$2 > rgb.$3),
                isTrue,
                reason: 'The lifted paper silhouette rises above the flat page',
              );
              expect(pixels.at(forward ? 109 : 2, 97), (52, 52, 52));
            }
          }
          final end = await _frame(
            from,
            to,
            1,
            forward: forward,
            paperColor: paper,
          );
          final actualDestination = await _frame(
            to,
            from,
            0,
            paperColor: paper,
          );
          expect(
            end.bytes.buffer.asUint8List(),
            actualDestination.bytes.buffer.asUint8List(),
          );
        }
      }
    },
  );

  test(
    'empty boundary slots and off-panel pixels remain transparent',
    () async {
      final boundary = [current[0], const PageTurnLeaf(bounds: _right)];
      final p = await _frame(boundary, next, .25);
      expect(p.at(205, 100), (52, 52, 52));
      final end = await _frame(next, boundary, 1, forward: false);
      expect(end.at(207, 115), (52, 52, 52));
      expect(end.at(2, 115), (52, 52, 52));
    },
  );
}
