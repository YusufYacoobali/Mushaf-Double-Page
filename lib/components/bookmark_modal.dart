import 'package:mushaf_two_page/utils/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:mushaf_two_page/models/bookmark.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

import '../pages/bookmark.dart';

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
    final palette = AppPalette.of(context);

    showModalBottomSheet(
      sheetAnimationStyle: AppMotion.style(context),
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(context).viewPadding.bottom;
            final sortedBookmarks = [...bookmarks]
              ..sort((a, b) {
                final byPage = a.pageNumber.compareTo(b.pageNumber);
                if (byPage != 0) return byPage;
                // Same page: the page bookmark first, then ayahs in order.
                return (a.ayah ?? -1).compareTo(b.ayah ?? -1);
              });
            return Container(
              height:
                  (isLandscape ? screenHeight * 0.85 : screenHeight * 0.65) +
                  bottomInset,
              decoration: BoxDecoration(
                color: palette.scaffold,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow,
                    blurRadius: 22,
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
                        color: palette.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bookmarks',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${sortedBookmarks.length} saved',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () {
                            onAddBookmark();
                            setModalState(() {});
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: palette.accent,
                            foregroundColor: palette.onAccent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.bookmark_add_rounded),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: sortedBookmarks.isEmpty
                        ? Center(
                            child: Text(
                              'No bookmarks yet',
                              style: TextStyle(
                                color: palette.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
                            itemCount: sortedBookmarks.length,
                            itemBuilder: (context, i) {
                              final bookmark = sortedBookmarks[i];
                              return BookmarkWidget(
                                bookmark: bookmark,
                                palette: palette,
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
