import 'package:flutter/material.dart';
import 'package:mushaf_two_page/models/bookmark.dart';

class BookmarkWidget extends StatefulWidget {
  final Bookmark bookmark;
  final Function(Bookmark) onBookmarkToggled;
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

  void _toggleBookmark() {
    setState(() {
      isBookmarked = !isBookmarked;
    });
    widget.onBookmarkToggled(widget.bookmark);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onPagePressed(widget.bookmark),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        decoration: BoxDecoration(
          color: const Color(0xFFFBFBFB),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: const Color(0xFFD6D6D6)),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 3,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ListTile(
          contentPadding:
          const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          title: Text(
            widget.bookmark.surah ?? 'Unknown Surah', // handle null
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2A6767),
            ),
          ),
          subtitle: Text(
            'Page ${widget.bookmark.pageNumber}',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: const Color(0xFFD9B44A),
              size: 30,
            ),
            onPressed: _toggleBookmark,
          ),
        ),
      ),
    );
  }
}
