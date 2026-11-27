import 'package:flutter/material.dart';
import '../components/nav_tile.dart';
import '../components/navigation_list_view.dart';
import 'juz_mapper.dart';
import 'page_ayah_index.dart';

class JuzList extends StatefulWidget {
  const JuzList({
    super.key,
    required this.onJump,
    required this.mushaf,
    this.currentJuz,
    this.onJumpToSurah,
  });

  final void Function(int) onJump;
  final void Function(int surah, int page)? onJumpToSurah;
  final String mushaf;
  final int? currentJuz;

  @override
  State<JuzList> createState() => _JuzListState();
}

class _JuzListState extends State<JuzList> {
  int? expanded;
  static const labels = ['Quarter 2 · ¼', 'Quarter 3 · ½', 'Quarter 4 · ¾'];

  Future<void> jump(int juz, int quarter) async {
    if (!PageAyahIndex.isReady) await PageAyahIndex.load();
    if (!mounted) return;
    final target = juzDestination(juz, quarter, widget.mushaf);
    Navigator.pop(context);
    final jumpToSurah = widget.onJumpToSurah;
    if (jumpToSurah == null) {
      widget.onJump(target.page);
    } else {
      jumpToSurah(target.surah, target.page);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationListView(
      storageKey: 'juz-${widget.mushaf}',
      itemCount: 30,
      initialIndex: (widget.currentJuz ?? 1) - 1,
      itemExtentBuilder: (context, width, index) {
        final juz = index + 1;
        final header = NavTile.extentFor(
          context,
          width,
          'Juz $juz',
          trailingWidth: 48,
        );
        return header +
            (expanded == juz
                ? labels.fold(
                    0.0,
                    (height, label) =>
                        height + NavTile.extentFor(context, width - 12, label),
                  )
                : 0.0);
      },
      itemBuilder: (context, index) {
        final juz = index + 1;
        final open = juz == expanded;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NavTile(
              number: juz,
              title: 'Juz $juz',
              selected: juz == widget.currentJuz,
              onTap: () => jump(juz, 1),
              trailing: SizedBox(
                width: 48,
                height: 42,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: '${open ? "Hide" : "Show"} quarters of Juz $juz',
                  icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => expanded = open ? null : juz),
                ),
              ),
            ),
            if (open)
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: NavTile(
                    number: i + 2,
                    title: labels[i],
                    onTap: () => jump(juz, i + 2),
                  ),
                ),
          ],
        );
      },
    );
  }
}
