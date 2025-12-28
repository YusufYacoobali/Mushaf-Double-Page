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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onPagePressed(widget.bookmark),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFBFBFB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFD6D6D6),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.bookmark.surah ?? 'Unknown Surah',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2A6767),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Page ${widget.bookmark.pageNumber}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _toggleBookmark,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.bookmark_rounded,
                    size: 22,
                    color: Color(0xFFD9B44A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
