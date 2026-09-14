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

class _PanelState extends State<_Panel> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
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
        child: Column(
          children: [
            const SizedBox(height: 40),

            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _tabs.index == 0
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

            _BottomSelector(index: _tabs.index, onTap: _tabs.animateTo),

            const SizedBox(height: 20),
          ],
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
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: index == 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  width: segmentWidth,
                  height: 36,
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
      child: GestureDetector(
        onTap: () => onTap(i),
        child: SizedBox(
          height: 36,
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
    );
  }
}
