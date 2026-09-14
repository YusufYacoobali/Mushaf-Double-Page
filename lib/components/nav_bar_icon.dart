import 'package:flutter/material.dart';
import '../utils/app_palette.dart';
import '../utils/app_motion.dart';

Widget barIcon({
  required IconData icon,
  required VoidCallback onPressed,
  required AppPalette palette,
  bool compact = true,
}) {
  final (label, kind) = switch (icon) {
    Icons.headphones_rounded => ('Audio', 0),
    Icons.chat_outlined => ('Notes', 1),
    Icons.menu_book_outlined => ('Quran', 2),
    Icons.bookmarks_rounded => ('Bookmarks', 3),
    _ => ('Settings', 4),
  };
  final selected = kind == 2;
  final foreground = selected ? const Color(0xFFE2C78D) : palette.readerIcon;
  return Tooltip(
    message: label == 'Notes' ? 'Translations, tafseer & notes' : label,
    child: Semantics(
      button: true,
      label: label,
      selected: selected,
      child: PressMotion(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              constraints: BoxConstraints(minHeight: compact ? 44 : 58),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF494139), Color(0xFF262321)],
                      )
                    : null,
                borderRadius: BorderRadius.circular(20),
                border: selected
                    ? Border.all(
                        color: const Color(0xFFB69B68).withValues(alpha: .5),
                      )
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomPaint(
                    size: const Size(25, 25),
                    painter: _ReaderIconPainter(kind, foreground),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 5),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Fine, rounded strokes shared by every reader destination.
class _ReaderIconPainter extends CustomPainter {
  const _ReaderIconPainter(this.kind, this.color);
  final int kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (kind) {
      case 0:
        path.moveTo(4, 15);
        path.lineTo(4, 10);
        path.cubicTo(4, 0, 20, 0, 20, 10);
        path.lineTo(20, 15);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 11, 4, 9),
            const Radius.circular(2),
          ),
          p,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(17, 11, 4, 9),
            const Radius.circular(2),
          ),
          p,
        );
      case 1:
        path.moveTo(5, 3);
        path.lineTo(19, 3);
        path.quadraticBezierTo(21, 3, 21, 5);
        path.lineTo(21, 15);
        path.quadraticBezierTo(21, 17, 19, 17);
        path.lineTo(11, 17);
        path.lineTo(6, 21);
        path.lineTo(6, 17);
        path.lineTo(5, 17);
        path.quadraticBezierTo(3, 17, 3, 15);
        path.lineTo(3, 5);
        path.quadraticBezierTo(3, 3, 5, 3);
        for (final x in [8.0, 12.0, 16.0]) {
          canvas.drawCircle(Offset(x, 10), .7, p);
        }
      case 2:
        path.moveTo(12, 5);
        path.quadraticBezierTo(7, 1, 2, 3);
        path.lineTo(2, 20);
        path.quadraticBezierTo(7, 18, 12, 22);
        path.quadraticBezierTo(17, 18, 22, 20);
        path.lineTo(22, 3);
        path.quadraticBezierTo(17, 1, 12, 5);
        path.lineTo(12, 22);
        for (final y in [7.0, 11.0, 15.0]) {
          path.moveTo(5, y);
          path.lineTo(9, y + 1);
          path.moveTo(15, y + 1);
          path.lineTo(19, y);
        }
      case 3:
        path.moveTo(6, 3);
        path.lineTo(18, 3);
        path.lineTo(18, 22);
        path.lineTo(12, 17);
        path.lineTo(6, 22);
        path.close();
      default:
        canvas.drawCircle(const Offset(12, 12), 7, p);
        canvas.drawCircle(const Offset(12, 12), 2.5, p);
        for (var i = 0; i < 8; i++) {
          canvas.save();
          canvas.translate(12, 12);
          canvas.rotate(i * 3.14159265 / 4);
          canvas.drawLine(const Offset(0, 8), const Offset(0, 10), p);
          canvas.restore();
        }
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_ReaderIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
