import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';

import '../components/nav_tile.dart';

class SurahList extends StatelessWidget {
  final void Function(int pageIndex) onJump;

  const SurahList(void Function(int pageIndex) onJumpToPage, {super.key, required this.onJump});

  @override
  Widget build(BuildContext context) {
    final surahs = surahRanges.where((s) => s.surah > 0).toList();
    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: surahs.length,
      itemBuilder: (_, i) {
        final surah = surahs[i];

        return NavTile(
          number: surah.surah,
          title: surah.name,
          englishTitle: surah.english,
          onTap: () {
            Navigator.pop(context);
            onJump(pageFromSurah(surah.surah));
          },
        );
      },
    );
  }
}