import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../components/nav_tile.dart';
import '../components/navigation_list_view.dart';
import 'app_motion.dart';
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

class _JuzListState extends State<JuzList> with SingleTickerProviderStateMixin {
  int? expanded;
  static const fractions = ['¼', '½', '¾'];

  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: 1,
  );
  // Snapshot the visible heights on each tap so even a rapid reversal is continuous.
  var _start = List<double>.filled(30, 0);

  double _openness(int index) {
    final target = expanded == index + 1 ? 1.0 : 0.0;
    return _start[index] +
        (target - _start[index]) * AppMotion.curve.transform(_motion.value);
  }

  void _toggle(int juz) {
    setState(() {
      _start = List.generate(30, _openness);
      expanded = expanded == juz ? null : juz;
      if (AppMotion.reduced(context)) {
        _motion.value = 1;
      } else {
        _motion.forward(from: 0);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) _motion.value = 1;
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth - NavigationListView.listPadding.horizontal;
        final headers = List.generate(
          30,
          (i) => NavTile.extentFor(
            context,
            width,
            'Juz ${i + 1}',
            trailingWidth: 48,
          ),
        );
        final childrenHeight = fractions.fold(
          0.0,
          (sum, fraction) =>
              sum + NavTile.extentFor(context, width - 12, '$fraction Juz'),
        );
        return AnimatedBuilder(
          animation: _motion,
          builder: (context, _) => NavigationListView(
            storageKey: 'juz-${widget.mushaf}',
            itemCount: headers.length,
            initialIndex: (widget.currentJuz ?? 1) - 1,
            itemExtentBuilder: (context, width, index) =>
                headers[index] + _openness(index) * childrenHeight,
            itemBuilder: (context, index) => _section(index),
          ),
        );
      },
    );
  }

  Widget _section(int index) {
    final juz = index + 1;
    final open = expanded == juz;
    final progress = _openness(index);
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
              icon: Transform.rotate(
                angle: math.pi * progress,
                child: const Icon(Icons.expand_more),
              ),
              onPressed: () => _toggle(juz),
            ),
          ),
        ),
        if (progress > 0)
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: ExcludeFocus(
                  excluding: !open,
                  child: ExcludeSemantics(
                    excluding: !open,
                    child: IgnorePointer(
                      ignoring: !open,
                      child: Opacity(
                        opacity: progress,
                        child: _quarterRows(juz),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _quarterRows(int juz) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < fractions.length; i++)
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: NavTile(
            number: i + 2,
            badgeText: fractions[i],
            title: '${fractions[i]} Juz',
            onTap: () => jump(juz, i + 2),
          ),
        ),
    ],
  );
}
