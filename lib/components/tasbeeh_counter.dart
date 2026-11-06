import 'package:flutter/material.dart';
import '../utils/app_motion.dart';

/// Physical shell and LCD are painted; the three controls are real buttons.
class TasbeehCounter extends StatelessWidget {
  const TasbeehCounter({
    super.key,
    required this.value,
    required this.onCount,
    required this.onUndo,
    required this.onReset,
  });
  final String value;
  final VoidCallback? onCount, onUndo, onReset;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 340 / 460,
    child: LayoutBuilder(
      builder: (context, box) {
        final scale = box.maxWidth / 340;
        Widget control(
          String label,
          double x,
          IconData icon,
          VoidCallback? tap,
        ) {
          final width = (62 * scale).clamp(48.0, double.infinity);
          final height = (56 * scale).clamp(64.0, double.infinity);
          return Positioned(
            left: x * scale - (width - 62 * scale) / 2,
            top: 181 * scale - (height - 56 * scale) / 2,
            width: width,
            height: height,
            child: Column(
              children: [
                Expanded(
                  child: IconButton(
                    tooltip: label,
                    onPressed: tap,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xffe9e1d0),
                      foregroundColor: const Color(0xff3d3831),
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: Color(0xffac9873)),
                    ),
                    icon: Icon(icon, size: 21 * scale),
                  ),
                ),
                SizedBox(height: 3 * scale),
                Text(
                  label,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 10 * scale,
                    color: const Color(0xffd0c4af),
                  ),
                ),
              ],
            ),
          );
        }

        return Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _CounterShell())),
            Positioned(
              left: 65 * scale,
              top: 76 * scale,
              width: 210 * scale,
              height: 68 * scale,
              child: Semantics(
                label: 'Tasbeeh count',
                value: value,
                child: ExcludeSemantics(
                  child: CustomPaint(painter: SevenSegmentDisplay(value)),
                ),
              ),
            ),
            control('Undo', 74, Icons.undo_rounded, onUndo),
            control('Reset', 204, Icons.restart_alt_rounded, onReset),
            Positioned(
              left: 81 * scale,
              top: 254 * scale,
              width: 178 * scale,
              height: 178 * scale,
              child: PressMotion(
                enabled: onCount != null,
                child: Semantics(
                  label: 'Count dhikr',
                  button: true,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xfffffcf1), Color(0xffded3bd)],
                      ),
                      border: Border.all(
                        color: const Color(0xffb5a27d),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 10,
                          offset: Offset(0, 6),
                        ),
                        BoxShadow(
                          color: Color(0x44ffffff),
                          blurRadius: 3,
                          offset: Offset(-1, -2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onCount,
                        excludeFromSemantics: true,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _CounterShell extends CustomPainter {
  Path _body() => Path()
    ..moveTo(87, 10)
    ..lineTo(253, 10)
    ..cubicTo(301, 10, 329, 40, 329, 92)
    ..lineTo(316, 299)
    ..cubicTo(311, 395, 267, 452, 170, 452)
    ..cubicTo(73, 452, 29, 395, 24, 299)
    ..lineTo(11, 92)
    ..cubicTo(11, 40, 39, 10, 87, 10)
    ..close();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 340, size.height / 460);
    final body = _body();
    canvas.drawShadow(body, const Color(0xff241b10), 14, true);
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfffffcf1), Color(0xffc7b999), Color(0xffeee6d7)],
        ).createShader(const Rect.fromLTWH(0, 0, 340, 460)),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xffae9161),
    );
    canvas.save();
    canvas.translate(170, 230);
    canvas.scale(.93, .95);
    canvas.translate(-170, -230);
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff454440), Color(0xff292a28), Color(0xff1d1e1d)],
        ).createShader(const Rect.fromLTWH(0, 0, 340, 460)),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xff907b56),
    );
    canvas.restore();
    final recess = RRect.fromRectAndRadius(
      const Rect.fromLTWH(47, 52, 246, 112),
      const Radius.circular(16),
    );
    canvas.drawRRect(recess, Paint()..color = const Color(0xff181a18));
    canvas.drawRRect(
      recess,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xff8d805f),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(57, 63, 226, 90),
        const Radius.circular(7),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff9eaa90), Color(0xffc1c7aa)],
        ).createShader(const Rect.fromLTWH(57, 63, 226, 90)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(59, 65, 222, 86),
        const Radius.circular(6),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x66383e2c),
    );
  }

  @override
  bool shouldRepaint(_CounterShell oldDelegate) => false;
}

/// Vector segments scale to any number of digits; no rollover or font glyph
/// substitution. A semantics value exposes the full number to screen readers.
class SevenSegmentDisplay extends CustomPainter {
  SevenSegmentDisplay(this.value);
  final String value;
  static const _digits = [
    0x3f,
    0x06,
    0x5b,
    0x4f,
    0x66,
    0x6d,
    0x7d,
    0x07,
    0x7f,
    0x6f,
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width / value.length;
    final digitWidth = width * .76;
    final height = (digitWidth * 1.85).clamp(0.0, size.height);
    final unit = height / 2;
    final thickness = height * .085;
    for (var i = 0; i < value.length; i++) {
      final number = int.tryParse(value[i]) ?? 0;
      final x = i * width + (width - digitWidth) / 2;
      final y = (size.height - height) / 2;
      final w = digitWidth;
      final segments = [
        Rect.fromLTWH(x + thickness, y, w - 2 * thickness, thickness),
        Rect.fromLTWH(
          x + w - thickness,
          y + thickness,
          thickness,
          unit - 1.5 * thickness,
        ),
        Rect.fromLTWH(
          x + w - thickness,
          y + unit + thickness / 2,
          thickness,
          unit - 1.5 * thickness,
        ),
        Rect.fromLTWH(
          x + thickness,
          y + height - thickness,
          w - 2 * thickness,
          thickness,
        ),
        Rect.fromLTWH(
          x,
          y + unit + thickness / 2,
          thickness,
          unit - 1.5 * thickness,
        ),
        Rect.fromLTWH(x, y + thickness, thickness, unit - 1.5 * thickness),
        Rect.fromLTWH(
          x + thickness,
          y + unit - thickness / 2,
          w - 2 * thickness,
          thickness,
        ),
      ];
      for (var n = 0; n < segments.length; n++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            segments[n],
            Radius.circular(thickness * .22),
          ),
          Paint()
            ..color = _digits[number] & (1 << n) != 0
                ? const Color(0xff28332b)
                : const Color(0x1228332b),
        );
      }
    }
  }

  @override
  bool shouldRepaint(SevenSegmentDisplay oldDelegate) =>
      oldDelegate.value != value;
}
