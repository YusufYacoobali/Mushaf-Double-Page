import 'package:flutter/material.dart';
import '../components/nav_tile.dart';
import '../components/navigation_list_view.dart';
import 'juz_mapper.dart';

class JuzList extends StatelessWidget {
  final void Function(int pageIndex) onJump;
  final String mushaf;
  final int? currentJuz;

  const JuzList(
    void Function(int pageIndex) onJumpToPage, {
    super.key,
    required this.onJump,
    required this.mushaf,
    this.currentJuz,
  });

  @override
  Widget build(BuildContext context) {
    final juzRanges = getJuzRanges(mushaf);
    return NavigationListView(
      storageKey: 'juz-$mushaf',
      itemCount: juzRanges.length,
      initialIndex: juzRanges.indexWhere((j) => j.juz == currentJuz),
      itemExtentBuilder: (context, width, index) =>
          NavTile.extentFor(context, width, 'Juz ${juzRanges[index].juz}'),
      itemBuilder: (_, i) {
        final juz = juzRanges[i];

        return NavTile(
          number: juz.juz,
          title: "Juz ${juz.juz}",
          selected: juz.juz == currentJuz,
          onTap: () {
            Navigator.pop(context);
            onJump(pageFromJuz(juz.juz, mushaf));
          },
        );
      },
    );
  }
}
