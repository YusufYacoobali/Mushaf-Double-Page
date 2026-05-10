import 'package:flutter/material.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

class BookmarkWidget extends StatefulWidget {
  final Bookmark bookmark;
  final AppPalette palette;

  /// Callback when bookmark icon is toggled (add/remove)
  final Function(Bookmark) onBookmarkToggled;

  /// Callback when the bookmark row itself is tapped
  /// Typically used to navigate to the bookmarked page
  final Function(Bookmark) onPagePressed;

  const BookmarkWidget({
    super.key,
    required this.bookmark,
    required this.palette,
    required this.onBookmarkToggled,
    required this.onPagePressed,
  });

  @override
  BookmarkWidgetState createState() => BookmarkWidgetState();
}

class BookmarkWidgetState extends State<BookmarkWidget> {
  bool isBookmarked = true;

  /// Toggles bookmark state and notifies parent widget
  void _toggleBookmark() {
    setState(() {
      isBookmarked = !isBookmarked;
    });
    // Inform parent so it can update storage / list state
    widget.onBookmarkToggled(widget.bookmark);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        shadowColor: palette.shadow,
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => widget.onPagePressed(widget.bookmark),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border.withValues(alpha: .65)),
            ),
            child: Row(
              children: [
                /// Bookmark icon badge
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: palette.accentSoft,
                  ),
                  child: Icon(Icons.bookmark_rounded, color: palette.accent),
                ),

                const SizedBox(width: 16),

                /// Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.bookmark.surah ?? 'Unknown Surah',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: palette.surfaceText,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Page ${widget.bookmark.pageNumber}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.surfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                /// Remove bookmark
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _toggleBookmark,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: palette.surfaceMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
