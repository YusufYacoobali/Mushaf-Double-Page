import 'package:flutter/material.dart';
import '../utils/app_palette.dart';

/// A visible, immediately draggable scroll thumb for both navigation lists.
class NavigationListView extends StatefulWidget {
  static const listPadding = EdgeInsets.fromLTRB(12, 12, 24, 12);

  const NavigationListView({
    super.key,
    required this.storageKey,
    required this.itemCount,
    required this.itemBuilder,
    this.initialIndex = 0,
    this.itemExtentBuilder,
  });
  final String storageKey;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int initialIndex;
  final double Function(BuildContext context, double width, int index)?
  itemExtentBuilder;

  @override
  State<NavigationListView> createState() => _NavigationListViewState();
}

class _NavigationListViewState extends State<NavigationListView> {
  ScrollController? _scroll;
  List<double>? _extents;
  int _metricsGeneration = 0;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final extents = widget.itemExtentBuilder == null
            ? null
            : [
                for (var i = 0; i < widget.itemCount; i++)
                  widget.itemExtentBuilder!(
                    context,
                    constraints.maxWidth -
                        NavigationListView.listPadding.horizontal,
                    i,
                  ),
              ];
        var initialOffset = 0.0;
        if (_scroll?.hasClients == true &&
            _scroll!.offset > NavigationListView.listPadding.top &&
            !_scroll!.position.isScrollingNotifier.value &&
            _extents != null &&
            extents != null &&
            !_sameExtents(_extents!, extents)) {
          var remaining = (_scroll!.offset - NavigationListView.listPadding.top)
              .clamp(0.0, double.infinity);
          var anchor = 0;
          while (anchor < _extents!.length - 1 &&
              remaining >= _extents![anchor]) {
            remaining -= _extents![anchor++];
          }
          final fraction = remaining / _extents![anchor];
          final target =
              NavigationListView.listPadding.top +
              extents.take(anchor).fold(0.0, (sum, height) => sum + height) +
              fraction * extents[anchor];
          final generation = ++_metricsGeneration;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                generation != _metricsGeneration ||
                !_scroll!.hasClients) {
              return;
            }
            final position = _scroll!.position;
            final offset = target.clamp(0.0, position.maxScrollExtent);
            if (!position.isScrollingNotifier.value &&
                (offset - position.pixels).abs() > .01) {
              _scroll!.jumpTo(offset);
            }
          });
        }
        _extents = extents;
        if (extents != null && extents.isNotEmpty && widget.initialIndex > 0) {
          final index = widget.initialIndex.clamp(0, extents.length - 1);
          final before = extents
              .take(index)
              .fold(0.0, (sum, value) => sum + value);
          final total = extents.fold(
            NavigationListView.listPadding.vertical,
            (sum, value) => sum + value,
          );
          initialOffset =
              (NavigationListView.listPadding.top +
                      before -
                      (constraints.maxHeight - extents[index]) / 2)
                  .clamp(
                    0.0,
                    (total - constraints.maxHeight).clamp(0.0, double.infinity),
                  );
        }
        _scroll ??= ScrollController(initialScrollOffset: initialOffset);
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: RawScrollbar(
            controller: _scroll,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            scrollbarOrientation: ScrollbarOrientation.right,
            thickness: 7,
            minThumbLength: 48,
            radius: const Radius.circular(8),
            crossAxisMargin: 4,
            mainAxisMargin: 8,
            thumbColor: palette.accent,
            trackColor: palette.accentSoft,
            trackBorderColor: Colors.transparent,
            child: ListView.builder(
              key: PageStorageKey(widget.storageKey),
              controller: _scroll,
              primary: false,
              padding: NavigationListView.listPadding,
              itemCount: widget.itemCount,
              itemExtentBuilder: extents == null
                  ? null
                  : (index, _) => extents[index],
              itemBuilder: widget.itemBuilder,
            ),
          ),
        );
      },
    );
  }

  bool _sameExtents(List<double> a, List<double> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => (a[i] - b[i]).abs() < .01);
}
