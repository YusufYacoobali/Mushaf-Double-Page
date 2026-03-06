import 'package:flutter/material.dart';
import '../components/nav_tile.dart';
import 'juz_mapper.dart';

class JuzList extends StatelessWidget {
  final void Function(int pageIndex) onJump;

  const JuzList(void Function(int pageIndex) onJumpToPage, {super.key, required this.onJump});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: juzRanges.length,
      itemBuilder: (_, i) {
        final juz = juzRanges[i];

        // return ListTile(
        //   title: Text("Juz ${juz.juz}"),
        //   onTap: () {
        //     Navigator.pop(context);
        //     onJump(pageFromJuz(juz.juz));
        //   },
        // );
        return NavTile(
          number: juz.juz,
          title: "Juz ${juz.juz}",
          onTap: () {
            Navigator.pop(context);
            onJump(pageFromJuz(juz.juz));
          },
        );
      },
    );
  }
}