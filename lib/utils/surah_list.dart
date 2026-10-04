import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';

import '../components/nav_tile.dart';
import '../components/navigation_list_view.dart';

class SurahList extends StatelessWidget {
  final void Function(int pageIndex) onJump;
  final String mushaf;
  final int? currentSurah;
  final void Function(int surah, int page)? onJumpToSurah;

  const SurahList(
    void Function(int pageIndex) onJumpToPage, {
    super.key,
    required this.onJump,
    required this.mushaf,
    this.currentSurah,
    this.onJumpToSurah,
  });

  @override
  Widget build(BuildContext context) {
    final surahs = getSurahRanges(mushaf).where((s) => s.surah > 0).toList();

    return NavigationListView(
      storageKey: 'surahs-$mushaf',
      itemCount: surahs.length,
      initialIndex: surahs.indexWhere((s) => s.surah == currentSurah),
      itemExtentBuilder: (context, width, index) => NavTile.extentFor(
        context,
        width,
        surahs[index].name,
        englishTitle: surahs[index].english,
      ),
      itemBuilder: (_, i) {
        final surah = surahs[i];

        return NavTile(
          number: surah.surah,
          title: surah.name,
          englishTitle: surah.english,
          selected: surah.surah == currentSurah,
          onTap: () {
            Navigator.pop(context);
            final page = pageFromSurah(surah.surah, mushaf);
            if (onJumpToSurah != null) {
              onJumpToSurah!(surah.surah, page);
            } else {
              onJump(page);
            }
          },
        );
      },
    );
  }
}
