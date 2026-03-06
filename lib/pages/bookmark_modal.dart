import 'package:flutter/material.dart';
import 'package:mushaf_two_page/models/bookmark.dart';

import 'bookmark.dart';

class BookmarksModal {
  static void show({
    required BuildContext context,
    required List<Bookmark> bookmarks,
    required bool isPortrait,
    required VoidCallback onAddBookmark,
    required void Function(Bookmark) onRemoveBookmark,
    required void Function(Bookmark) onJumpToBookmark,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewPadding.bottom;
            return Container(
                height: (isLandscape
                    ? screenHeight * 0.85
                    : screenHeight * 0.65) +
                    bottomInset,
                decoration: const BoxDecoration(
                  color: Color.fromARGB(255, 235, 243, 236),
                  borderRadius:
                  BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 14,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 8, bottom: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor.withOpacity(.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    // Add bookmark button
                    Container(
                      margin: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            onAddBookmark();
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.bookmark_add_rounded),
                          label: const Text('Bookmark this page'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            foregroundColor: Theme.of(context).colorScheme.onSurface,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Bookmark list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: bookmarks.length,
                      itemBuilder: (context, i) {
                        final bookmark = bookmarks[i];
                        return BookmarkWidget(
                          bookmark: bookmark,
                          onBookmarkToggled: (b) {
                            onRemoveBookmark(b);
                            setModalState(() {});
                          },
                          onPagePressed: (b) {
                            onJumpToBookmark(b);
                          },
                        );
                      },
                    ),
                  ),
                  ],
                ),
            );
          },
        );
      },
    );
  }
}