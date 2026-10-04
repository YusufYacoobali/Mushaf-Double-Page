import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/surah_list.dart';
import 'juz_list.dart';
import 'app_motion.dart';

class SurahJuzNavigator {
  static void show({
    required BuildContext context,
    required void Function(int pageIndex) onJumpToPage,
    required String mushaf,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Surah and Juz navigation",
      barrierColor: Colors.black54,
      transitionDuration: AppMotion.duration(context),
      pageBuilder: (_, _, _) => Align(
        alignment: Alignment.centerRight,
        child: _Panel(onJumpToPage: onJumpToPage, mushaf: mushaf),
      ),
      transitionBuilder: (context, anim, _, child) {
        if (AppMotion.reduced(context)) return child;
        final slide = Tween(
          begin: const Offset(.18, 0),
          end: Offset.zero,
        ).animate(anim.drive(CurveTween(curve: AppMotion.curve)));

        return FadeTransition(
          opacity: anim.drive(CurveTween(curve: AppMotion.curve)),
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
  }
}

class _Panel extends StatefulWidget {
  final void Function(int pageIndex) onJumpToPage;
  final String mushaf;

  const _Panel({required this.onJumpToPage, required this.mushaf});

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  int _index = 0;
  final _scrollPositions = PageStorageBucket();

  void _selectTab(int index) {
    if (index != _index) setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final palette = AppPalette.of(context);

    return Material(
      color: palette.scaffold,
      elevation: 12,
      shadowColor: palette.shadow,
      child: SizedBox(
        width: 320,
        height: height,
        child: SafeArea(
          minimum: const EdgeInsets.only(top: 12, bottom: 12),
          child: Column(
            children: [
              Expanded(
                child: PageStorage(
                  bucket: _scrollPositions,
                  child: MotionSwitcher(
                    offset: Offset.zero,
                    child: _index == 0
                        ? SurahList(
                            key: const ValueKey("surah"),
                            widget.onJumpToPage,
                            mushaf: widget.mushaf,
                            onJump: widget.onJumpToPage,
                          )
                        : JuzList(
                            key: const ValueKey("juz"),
                            widget.onJumpToPage,
                            onJump: widget.onJumpToPage,
                            mushaf: widget.mushaf,
                          ),
                  ),
                ),
              ),

              _BottomSelector(index: _index, onTap: _selectTab),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomSelector extends StatelessWidget {
  final int index;
  final void Function(int) onTap;

  const _BottomSelector({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(30),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / 2;

          return Stack(
            children: [
              AnimatedAlign(
                duration: AppMotion.duration(context, false),
                curve: Curves.easeOutCubic,
                alignment: index == 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  width: segmentWidth,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: palette.shadow,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),

              Row(
                children: [
                  _item("Surah", 0, palette),
                  _item("Juz", 1, palette),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _item(String text, int i, AppPalette palette) {
    final selected = index == i;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: PressMotion(
          child: InkWell(
            onTap: () => onTap(i),
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  text,
                  style: TextStyle(
                    color: selected ? palette.accent : palette.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
