import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/surah_list.dart';
import 'juz_list.dart';

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
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => const SizedBox(),
      transitionBuilder: (context, anim, _, __) {
        final slide = Tween(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          ),
        );

        return SlideTransition(
          position: slide,
          child: Align(
            alignment: Alignment.centerRight,
            child: _Panel(onJumpToPage: onJumpToPage, mushaf: mushaf,),
          ),
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

class _PanelState extends State<_Panel>
    with SingleTickerProviderStateMixin {
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

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 12,
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

            _BottomSelector(
              index: _tabs.index,
              onTap: _tabs.animateTo,
            ),

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

  const _BottomSelector({
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const bg = Color.fromARGB(255, 220, 232, 224);
    const active = Color(0xFF025C32);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: bg,
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),

              Row(
                children: [
                  _item("Surah", 0),
                  _item("Juz", 1),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _item(String text, int i) {
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
                color: selected
                    ? const Color(0xFF025C32)
                    : Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}