import 'package:flutter/material.dart';
import '../components/nav_tile.dart';
import 'juz_mapper.dart';

class JuzList extends StatelessWidget {
  final void Function(int pageIndex) onJump;
  final String mushaf;

  const JuzList(void Function(int pageIndex) onJumpToPage, {super.key, required this.onJump,  required this.mushaf});

  @override
  Widget build(BuildContext context) {
    final juzRanges = getJuzRanges(mushaf);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: juzRanges.length,
      itemBuilder: (_, i) {
        final juz = juzRanges[i];

        return NavTile(
          number: juz.juz,
          title: "Juz ${juz.juz}",
          onTap: () {
            Navigator.pop(context);
            onJump(pageFromJuz(juz.juz, mushaf));
          },
        );
      },
    );
  }
}