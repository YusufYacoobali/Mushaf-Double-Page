import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../components/reader_dock.dart';
import 'ios_display_regions.dart';
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
    this.navigationKey,
    required this.native,
    required this.isIPad,
  });
  final Widget child;
  final ReaderLayout layout;
  final double zoom;
  final int focusedPage;
  final List<int> visiblePages;
  final String edition;
  final bool Function() settled;
  final GlobalKey? navigationKey;
  final IosDisplayRegions native;
  final bool isIPad;
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
      Map<String, double> insets(EdgeInsets value) => {
        'left': value.left,
        'top': value.top,
        'right': value.right,
        'bottom': value.bottom,
      };
      bool? navigationExpanded;
      bool moving = false;
      Map<String, Object?>? scroll;
      void visit(Element element) {
        final current = element.widget;
        if (current is ExcludeSemantics && current.excluding) return;
        if (current is NavigationPullTab) {
          navigationExpanded = current.expanded;
          moving |= current.reveal != (current.expanded ? 1.0 : 0.0);
        }
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
            if (page == widget.focusedPage) {
              final scrollable = Scrollable.maybeOf(
                element,
                axis: Axis.vertical,
              );
              final position = scrollable?.position;
              final clip = scrollable?.context.findRenderObject();
              if (position != null &&
                  position.hasContentDimensions &&
                  clip is RenderBox) {
                final settled = !position.isScrollingNotifier.value;
                moving |= !settled;
                scroll = {
                  'viewport': rect(
                    MatrixUtils.transformRect(
                      clip.getTransformTo(null),
                      Offset.zero & clip.size,
                    ),
                  ),
                  'offset': position.pixels,
                  'min': position.minScrollExtent,
                  'max': position.maxScrollExtent,
                  'settled': settled,
                };
              }
            }
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
      if (moving) {
        schedule();
        return;
      }
      // Measure controls only for QA evidence. They never reduce page bounds.
      final navigationBox = widget.navigationKey?.currentContext
          ?.findRenderObject();
      final navigationBounds =
          navigationBox is RenderBox &&
              navigationBox.hasSize &&
              navigationBox.attached
          ? MatrixUtils.transformRect(
              navigationBox.getTransformTo(null),
              Offset.zero & navigationBox.size,
            )
          : null;
      final data = {
        'viewport': {'width': media.size.width, 'height': media.size.height},
        'pixelRatio': media.devicePixelRatio,
        'padding': insets(media.padding),
        'viewPadding': insets(media.viewPadding),
        'frameworkFeatures': [
          for (final feature in media.displayFeatures)
            {
              'bounds': rect(feature.bounds),
              'type': feature.type.name,
              'state': feature.state.name,
            },
        ],
        'native': {
          'viewport': {
            'width': widget.native.size.width,
            'height': widget.native.size.height,
          },
          'divisions': widget.native.rawDivisions,
          'closed': widget.native.closed,
          'isIPad': widget.isIPad,
        },
        'mode': widget.layout.pageMode.name,
        'sizing': widget.layout.sizing.name,
        'scroll': scroll,
        'navigationExpanded': navigationExpanded,
        'fit': widget.layout.fitPagesToViewport,
        'zoom': widget.zoom,
        'focusedPage': widget.focusedPage,
        'edition': widget.edition,
        'readingBounds': rect(widget.layout.usableContentBounds),
        'safeRegions': widget.layout.safeRegions.map(rect).toList(),
        'regions': widget.layout.pageRegions.map(rect).toList(),
        'pages': pages,
        'controls': controls,
        'navigation': navigationExpanded == false
            ? controls['Open navigation']
            : navigationBounds == null
            ? null
            : rect(navigationBounds),
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
  Widget build(BuildContext context) {
    if (!const bool.fromEnvironment('READER_LAYOUT_QA')) return widget.child;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        schedule();
        return false;
      },
      child: widget.child,
    );
  }
}
