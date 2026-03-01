import 'package:flutter/material.dart';

class SurahList extends StatelessWidget {
  final void Function(int pageIndex) onJump;

  const SurahList(void Function(int pageIndex) onJumpToPage, {super.key, required this.onJump});

  @override
  Widget build(BuildContext context) {
    final surahs = List.generate(
      114,
          (i) => "Surah ${i + 1}",
    );

    return ListView.builder(
      itemCount: surahs.length,
      itemBuilder: (_, i) {
        return ListTile(
          title: Text(surahs[i]),
          onTap: () {
            Navigator.pop(context);
            onJump(_surahToPage(i + 1));
          },
        );
      },
    );
  }

  int _surahToPage(int surah) {
    // TODO: map surah → mushaf page
    return 0;
  }
}