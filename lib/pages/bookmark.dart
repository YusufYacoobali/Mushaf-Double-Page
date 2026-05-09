import 'package:flutter/material.dart';
import 'package:mushaf_two_page/models/bookmark.dart';

class BookmarkWidget extends StatefulWidget {
  final Bookmark bookmark;

  /// Callback when bookmark icon is toggled (add/remove)
  final Function(Bookmark) onBookmarkToggled;

  /// Callback when the bookmark row itself is tapped
  /// Typically used to navigate to the bookmarked page
  final Function(Bookmark) onPagePressed;

  const BookmarkWidget({
    super.key,
    required this.bookmark,
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
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Material(
        color: Color.fromARGB(255, 235, 243, 236),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => widget.onPagePressed(widget.bookmark),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: .15),
              ),
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
                    color: const Color(0xFF025C32).withValues(alpha: .15),
                  ),
                  child: const Icon(
                    Icons.bookmark_rounded,
                    color: Color(0xFF025C32),
                  ),
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Page ${widget.bookmark.pageNumber}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black,
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
                      color: Colors.black.withValues(alpha: .45),
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
