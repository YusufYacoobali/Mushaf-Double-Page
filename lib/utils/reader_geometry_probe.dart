import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'reader_layout.dart';

/// Debug-build diagnostics for comparing actual rendered frames with PNGs.
/// Ordinary builds do not traverse the tree or write diagnostic files.
class ReaderGeometryProbe extends StatefulWidget {
  const ReaderGeometryProbe({
    super.key,
    required this.child,
    required this.layout,
    required this.zoom,
    required this.focusedPage,
    required this.visiblePages,
    required this.edition,
    required this.settled,
    this.navigationBounds,
  });
  final Widget child;
  final ReaderLayout layout;
  final double zoom;
  final int focusedPage;
  final List<int> visiblePages;
  final String edition;
  final bool Function() settled;
  final Rect? navigationBounds;
  @override
  State<ReaderGeometryProbe> createState() => _ReaderGeometryProbeState();
}

class _ReaderGeometryProbeState extends State<ReaderGeometryProbe> {
  bool pending = false;
  String? lastFrame;
  int revision = 0;
  void schedule() {
    if (!const bool.fromEnvironment('READER_LAYOUT_QA') || pending) return;
    pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      pending = false;
      if (!mounted) return;
      if (!widget.settled()) {
        schedule();
        return;
      }
      final media = MediaQuery.of(context);
      final pages = <String, Object?>{};
      final controls = <String, Object?>{};
      Map<String, double> rect(Rect r) => {
        'left': r.left,
        'top': r.top,
        'width': r.width,
        'height': r.height,
      };
      void visit(Element element) {
        final current = element.widget;
        if (current is ExcludeSemantics && current.excluding) return;
        final label = current is IconButton
            ? current.tooltip
            : current is Tooltip
            ? current.message
            : null;
        if (label != null) {
          final box = element.findRenderObject();
          if (box is RenderBox && box.hasSize && box.attached) {
            controls[label] = rect(
              MatrixUtils.transformRect(
                box.getTransformTo(null),
                Offset.zero & box.size,
              ),
            );
          }
        }
        final key = element.widget.key;
        if (key is ValueKey<String> && key.value.startsWith('quran-page-')) {
          final page = int.tryParse(key.value.substring('quran-page-'.length));
          final box = element.findRenderObject();
          if (widget.visiblePages.contains(page) &&
              box is RenderBox &&
              box.hasSize) {
            pages['$page'] = rect(
              MatrixUtils.transformRect(
                box.getTransformTo(null),
                Offset.zero & box.size,
              ),
            );
          }
        }
        element.visitChildElements(visit);
      }

      context.visitChildElements(visit);
      final data = {
        'viewport': {'width': media.size.width, 'height': media.size.height},
        'pixelRatio': media.devicePixelRatio,
        'mode': widget.layout.pageMode.name,
        'fit': widget.layout.fitPagesToViewport,
        'zoom': widget.zoom,
        'focusedPage': widget.focusedPage,
        'edition': widget.edition,
        'readingBounds': rect(widget.layout.usableContentBounds),
        'regions': widget.layout.pageRegions.map(rect).toList(),
        'pages': pages,
        'controls': controls,
        'navigation': widget.navigationBounds == null
            ? null
            : rect(widget.navigationBounds!),
      };
      final frame = jsonEncode(data);
      if (lastFrame != frame) {
        lastFrame = frame;
        schedule();
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      data['timestamp'] = DateTime.now().toUtc().toIso8601String();
      final currentRevision = ++revision;
      final directory = await getApplicationDocumentsDirectory();
      if (!mounted || currentRevision != revision) return;
      final temp = File(
        '${directory.path}/reader-geometry-$currentRevision.tmp',
      );
      await temp.writeAsString(jsonEncode(data));
      if (currentRevision == revision) {
        await temp.rename('${directory.path}/reader-geometry.json');
      } else {
        await temp.delete();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    schedule();
  }

  @override
  void didUpdateWidget(covariant ReaderGeometryProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    schedule();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
