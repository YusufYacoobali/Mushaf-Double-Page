import 'package:flutter/material.dart';
import '../utils/app_palette.dart';

/// A visible, immediately draggable scroll thumb for both navigation lists.
class NavigationListView extends StatefulWidget {
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
                    constraints.maxWidth - 36,
                    i,
                  ),
              ];
        var initialOffset = 0.0;
        if (extents != null && extents.isNotEmpty && widget.initialIndex > 0) {
          final index = widget.initialIndex.clamp(0, extents.length - 1);
          final before = extents
              .take(index)
              .fold(0.0, (sum, value) => sum + value);
          final total = extents.fold(24.0, (sum, value) => sum + value);
          initialOffset =
              (12 + before - (constraints.maxHeight - extents[index]) / 2)
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
              padding: const EdgeInsets.fromLTRB(12, 12, 24, 12),
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
}
