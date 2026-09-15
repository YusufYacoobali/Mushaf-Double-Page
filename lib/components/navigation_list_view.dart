import 'package:flutter/material.dart';
import '../utils/app_palette.dart';

/// A visible, immediately draggable scroll thumb for both navigation lists.
class NavigationListView extends StatefulWidget {
  const NavigationListView({
    super.key,
    required this.storageKey,
    required this.itemCount,
    required this.itemBuilder,
  });
  final String storageKey;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<NavigationListView> createState() => _NavigationListViewState();
}

class _NavigationListViewState extends State<NavigationListView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
  }
}
