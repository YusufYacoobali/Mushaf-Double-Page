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
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Container(
                height: isLandscape
                    ? screenHeight * 0.85
                    : screenHeight * 0.65,
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
                    const SizedBox(height: 10),

                    // Add bookmark button
                    Container(
                      margin: const EdgeInsets.all(12),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          onAddBookmark();
                          setModalState(() {});
                        },
                        icon: const Icon(Icons.bookmark_add_rounded),
                        label: const Text('Bookmark this page'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
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
              ),
            );
          },
        );
      },
    );
  }
}




// void _showBookmarksModal() {
//   final screenHeight = MediaQuery.of(context).size.height;
//   final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
//
//   showModalBottomSheet(
//     context: context,
//     isScrollControlled: true,
//     backgroundColor: Colors.transparent,
//     builder: (context) {
//       return StatefulBuilder(
//         builder: (context, setModalState) {
//           return SafeArea(
//             child: Container(
//               height: isLandscape ? screenHeight * 0.85 : screenHeight * 0.65,
//               decoration: const BoxDecoration(
//                 color: Color.fromARGB(255, 235, 243, 236),
//                 borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.black26,
//                     blurRadius: 14,
//                     offset: Offset(0, -4),
//                   ),
//                 ],
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.stretch,
//                 children: [
//                   // Drag handle
//                   Padding(
//                     padding: const EdgeInsets.only(top: 10, bottom: 6),
//                     child: Center(
//                       child: Container(
//                         width: 36,
//                         height: 4,
//                         decoration: BoxDecoration(
//                           color: Colors.black26,
//                           borderRadius: BorderRadius.circular(2),
//                         ),
//                       ),
//                     ),
//                   ),
//
//                   // Fancy bookmark button
//                   Container(
//                     margin: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(
//                       borderRadius: BorderRadius.circular(14),
//                       boxShadow: [
//                         BoxShadow(
//                           color: Colors.black.withOpacity(0.08),
//                           blurRadius: 10,
//                           offset: const Offset(0, 4),
//                         ),
//                       ],
//                     ),
//                     child: Material(
//                       color: const Color(0xFFFBFBFB),
//                       borderRadius: BorderRadius.circular(14),
//                       child: InkWell(
//                         borderRadius: BorderRadius.circular(14),
//                         onTap: () {
//                           _addBookmark();  // your existing function
//                           setModalState(() {}); // refresh modal
//                         },
//                         child: Padding(
//                           padding: const EdgeInsets.symmetric(
//                             vertical: 14,
//                             horizontal: 18,
//                           ),
//                           child: Row(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: const [
//                               Icon(
//                                 Icons.bookmark_add_rounded,
//                                 color: Color(0xFF2A6767),
//                                 size: 26,
//                               ),
//                               SizedBox(width: 10),
//                               Text(
//                                 'Bookmark this page',
//                                 style: TextStyle(
//                                   fontSize: 17,
//                                   fontWeight: FontWeight.w600,
//                                   color: Color(0xFF2A6767),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ),
//
//                   // Bookmark list
//                   Expanded(
//                     child: ListView.builder(
//                       padding: const EdgeInsets.only(bottom: 12),
//                       itemCount: _bookmarks.length,
//                       itemBuilder: (context, i) {
//                         final bookmark = _bookmarks[i];
//                         return BookmarkWidget(
//                           bookmark: bookmark,
//                           onBookmarkToggled: (b) {
//                             setState(() => _bookmarks.remove(b));
//                             StorageManager.saveBookmarks(_bookmarks);
//                             setModalState(() {}); // refresh modal UI
//                           },
//                           onPagePressed: (b) {
//                             final page = PageMapper.bookmarkGoToMapper(
//                               b.pageNumber,
//                               _isPortrait,
//                             );
//                             _pageController.jumpToPage(page); // your existing controller
//
//                             final logical = _logicalFromPageIndex(page, _isPortrait);
//
//                             setState(() {
//                               _logicalPage = logical;
//                             });
//                           },
//                         );
//                       },
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           );
//         },
//       );
//     },
//   );
// }