import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The painted bounds of one physical leaf in reader coordinates. A missing
/// image denotes an empty slot at the beginning or end of the Mushaf.
class PageTurnLeaf {
  const PageTurnLeaf({required this.bounds, this.image});

  final Rect bounds;
  final ui.Image? image;
}

/// A frozen pair of reader surfaces. The host owns their images and supplies
/// leaves in physical left-to-right order, independently of page numbering.
class QuranPageTurnPainter extends CustomPainter {
  const QuranPageTurnPainter({
    required this.source,
    required this.destination,
    required this.forward,
    required this.progress,
    required this.clipRegions,
    required this.paperColor,
  }) : assert(source.length == destination.length),
       assert(source.length == 1 || source.length == 2);

  final List<PageTurnLeaf> source;
  final List<PageTurnLeaf> destination;
  final bool forward;
  final double progress;
  final List<Rect> clipRegions;
  final Color paperColor;

  static const int _strips = 40;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final clip = Path();
    for (final rect in clipRegions) {
      clip.addRect(rect);
    }
    canvas.clipPath(clip);
    final t = progress.clamp(0.0, 1.0);
    if (t == 0 || t == 1) {
      for (final leaf in t == 0 ? source : destination) {
        _paintFlat(canvas, leaf);
      }
    } else {
      final single = source.length == 1;
      final lifting = single || forward ? 0 : 1;
      final landing = single ? 0 : 1 - lifting;
      _paintFlat(canvas, destination[lifting]);
      if (!single) _paintFlat(canvas, source[landing]);
      final front = source[lifting];
      final back = destination[landing];
      if (single) {
        // The turned sheet exits through its binding edge. The revealed page
        // has already been drawn at its own (possibly unpinched) bounds.
        // Allow the curved top and bottom edges to lift into the reading
        // margins, while keeping the reverse flap inside the binding edge.
        canvas.clipRect(
          Rect.fromLTRB(front.bounds.left, 0, front.bounds.right, size.height),
        );
      }
      _paintSheet(canvas, front, back, t, single);
    }
    canvas.restore();
  }

  static void _paintFlat(Canvas canvas, PageTurnLeaf leaf) {
    final image = leaf.image;
    if (image == null || leaf.bounds.isEmpty) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      leaf.bounds,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  void _paintSheet(
    Canvas canvas,
    PageTurnLeaf front,
    PageTurnLeaf back,
    double t,
    bool single,
  ) {
    final from = front.bounds;
    final to = single ? from : back.bounds;
    if (from.isEmpty || to.isEmpty) return;
    final angle = math.pi * t;
    final lift = math.sin(angle);
    final width = ui.lerpDouble(from.width, to.width, t)!;
    final top = ui.lerpDouble(from.top, to.top, t)!;
    final bottom = ui.lerpDouble(from.bottom, to.bottom, t)!;
    final binding = single
        ? (forward ? from.right : from.left)
        : ui.lerpDouble(
            forward ? from.right : from.left,
            forward ? to.left : to.right,
            t,
          )!;
    final sign = forward ? -1.0 : 1.0;

    // Unroll the sheet from binding to free edge. The height above the desk
    // grows along this curve, so drawing strips in this order also places the
    // returning face in front of the portion it covers.
    final columns = <_SheetColumn>[];
    for (var i = 0; i <= _strips; i++) {
      final u = i / _strips;
      final section = single
          ? _rollingSection(u, t, lift)
          : _rotatingSection(u, angle, lift);
      final x = binding + sign * section.x * width;
      final rise = section.z * math.min(width * .065, 28);
      columns.add(
        _SheetColumn(
          u,
          section.angle,
          Offset(x, top - rise),
          Offset(x, bottom + rise * .35),
        ),
      );
    }

    final outline = Path()
      ..addPolygon([
        for (final c in columns) c.top,
        for (final c in columns.reversed) c.bottom,
      ], true);
    canvas.drawPath(
      outline.shift(Offset(-sign * 3 * lift, 1.5 * lift)),
      Paint()
        ..color = Colors.black.withValues(alpha: .20 * lift)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1 + 3 * lift),
    );

    // The tangent crosses vertical at most once. Draw one textured strip mesh
    // per visible face; texture coordinates of the reverse face run from the
    // binding to the opposite edge in the destination's reading orientation.
    var split = 0;
    while (split < _strips &&
        (columns[split].angle + columns[split + 1].angle) / 2 < math.pi / 2) {
      split++;
    }
    _paintFace(canvas, columns, 0, split, front.image, mirror: forward);
    _paintFace(
      canvas,
      columns,
      split,
      _strips,
      single ? null : back.image,
      mirror: !forward,
      underside: single,
    );

    final edge = columns.last;
    canvas.drawLine(
      edge.top,
      edge.bottom,
      Paint()
        ..strokeWidth = .75
        ..color = Colors.black.withValues(alpha: .22 * lift),
    );
  }

  /// Integral of a circular arc whose tangent changes gradually along the
  /// rotating sheet. At rest the front and back are exactly flat.
  static _Section _rotatingSection(double u, double angle, double lift) {
    final curvature = 1.5 * lift;
    final startAngle = angle - curvature / 2;
    final tangent = startAngle + curvature * u;
    if (curvature < .000001) {
      return _Section(u * math.cos(angle), u * lift, angle);
    }
    return _Section(
      (math.sin(tangent) - math.sin(startAngle)) / curvature,
      (math.cos(startAngle) - math.cos(tangent)) / curvature,
      tangent,
    );
  }

  /// In a single-page window a cylindrical fold travels from the free edge to
  /// the binding. The flap folds back across the outgoing printed face.
  static _Section _rollingSection(double u, double t, double lift) {
    final arc = .38 * lift;
    final start = 1 - t - arc / 2;
    final along = u - start;
    if (along <= 0) return _Section(u, 0, 0);
    final radius = arc / math.pi;
    if (along >= arc) {
      return _Section(start - (along - arc), 2 * radius, math.pi);
    }
    final angle = along / radius;
    return _Section(
      start + radius * math.sin(angle),
      radius * (1 - math.cos(angle)),
      angle,
    );
  }

  void _paintFace(
    Canvas canvas,
    List<_SheetColumn> columns,
    int first,
    int last,
    ui.Image? image, {
    required bool mirror,
    bool underside = false,
  }) {
    if (first == last || (image == null && !underside)) return;
    final vertices = <Offset>[];
    final colors = <Color>[];
    final texels = <Offset>[];
    for (var i = first; i <= last; i++) {
      final c = columns[i];
      vertices.addAll([c.top, c.bottom]);
      final shade = (255 * (1 - .17 * math.sin(c.angle))).round().clamp(0, 255);
      final tint = underside
          ? Color.fromARGB(
              255,
              (paperColor.r * shade).round(),
              (paperColor.g * shade).round(),
              (paperColor.b * shade).round(),
            )
          : Color.fromARGB(255, shade, shade, shade);
      colors.addAll([tint, tint]);
      if (image != null) {
        final x = (mirror ? 1 - c.u : c.u) * image.width;
        texels.addAll([Offset(x, 0), Offset(x, image.height.toDouble())]);
      }
    }
    final mesh = ui.Vertices(
      ui.VertexMode.triangleStrip,
      vertices,
      colors: colors,
      textureCoordinates: image == null ? null : texels,
    );
    final shader = image == null
        ? null
        : ui.ImageShader(
            image,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity().storage,
            filterQuality: FilterQuality.low,
          );
    canvas.drawVertices(
      mesh,
      shader == null ? BlendMode.dst : BlendMode.modulate,
      Paint()
        ..color = Colors.white
        ..shader = shader
        ..isAntiAlias = true,
    );
    shader?.dispose();
    mesh.dispose();
  }

  @override
  bool shouldRepaint(QuranPageTurnPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      forward != oldDelegate.forward ||
      source != oldDelegate.source ||
      destination != oldDelegate.destination ||
      clipRegions != oldDelegate.clipRegions ||
      paperColor != oldDelegate.paperColor;
}

class _Section {
  const _Section(this.x, this.z, this.angle);
  final double x, z, angle;
}

class _SheetColumn {
  const _SheetColumn(this.u, this.angle, this.top, this.bottom);
  final double u, angle;
  final Offset top, bottom;
}
