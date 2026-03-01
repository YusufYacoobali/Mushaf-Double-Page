import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';

class SurahList extends StatelessWidget {
  final void Function(int pageIndex) onJump;

  const SurahList(void Function(int pageIndex) onJumpToPage, {super.key, required this.onJump});

  @override
  Widget build(BuildContext context) {
    final surahs = surahRanges.where((s) => s.surah > 0).toList();

    return ListView.builder(
      itemCount: surahs.length,
      itemBuilder: (_, i) {
        final surah = surahs[i];
        return ListTile(
          title: Text("${surah.surah}. ${surah.name}"),
          onTap: () {
            Navigator.pop(context);
            onJump(pageFromSurah(surah.surah));
          },
        );
      },
    );
  }
}