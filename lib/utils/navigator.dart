import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/surah_list.dart';
import 'juz_list.dart';
import 'app_motion.dart';
import 'surah_mapper.dart';
import 'juz_mapper.dart';
import 'reader_layout.dart';

class SurahJuzNavigator {
  static void show({
    required BuildContext context,
    required void Function(int pageIndex) onJumpToPage,
    required String mushaf,
    int currentLogicalPage = 1,
    int? currentSurah,
    void Function(int surah, int page)? onJumpToSurah,
  }) {
    final sourceContext = context;
    showGeneralDialog(
      context: context,
      anchorPoint: const Offset(double.maxFinite, 0),
      barrierDismissible: true,
      barrierLabel: "Surah and Juz navigation",
      barrierColor: Colors.black54,
      transitionDuration: AppMotion.duration(context),
      pageBuilder: (context, _, _) => LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final region = navigationRegion(
            size,
            MediaQuery.paddingOf(context),
            MediaQuery.displayFeaturesOf(context),
          );
          final window = sourceContext.mounted
              ? MediaQuery.sizeOf(sourceContext)
              : size;
          final width = navigatorPanelWidth(window, region);
          return Stack(
            children: [
              Positioned.fromRect(
                rect: Rect.fromLTWH(
                  region.right - width,
                  region.top,
                  width,
                  region.height,
                ),
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(width, region.height),
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                    displayFeatures: const [],
                  ),
                  child: _Panel(
                    onJumpToPage: onJumpToPage,
                    mushaf: mushaf,
                    currentLogicalPage: currentLogicalPage,
                    currentSurah: currentSurah,
                    onJumpToSurah: onJumpToSurah,
                  ),
                ),
              ),
            ],
          );
        },
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
  final int currentLogicalPage;
  final int? currentSurah;
  final void Function(int surah, int page)? onJumpToSurah;

  const _Panel({
    required this.onJumpToPage,
    required this.mushaf,
    required this.currentLogicalPage,
    this.currentSurah,
    this.onJumpToSurah,
  });

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
    final palette = AppPalette.of(context);
    final surahs = surahsFromLogicalPage(
      widget.currentLogicalPage,
      widget.mushaf,
    ).where((s) => s.surah > 0);
    final currentSurah =
        widget.currentSurah ?? (surahs.isEmpty ? null : surahs.first.surah);
    final juz = getJuzRanges(
      widget.mushaf,
    ).where((j) => j.start <= widget.currentLogicalPage);
    final currentJuz = juz.isEmpty ? null : juz.last.juz;

    return Material(
      color: palette.scaffold,
      elevation: 12,
      shadowColor: palette.shadow,
      child: SizedBox.expand(
        key: const ValueKey('surah-juz-panel'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Expanded(
                child: PageStorage(
                  bucket: _scrollPositions,
                  child: IndexedStack(
                    index: _index,
                    children: [
                      SurahList(
                        key: const ValueKey("surah"),
                        widget.onJumpToPage,
                        mushaf: widget.mushaf,
                        onJump: widget.onJumpToPage,
                        currentSurah: currentSurah,
                        onJumpToSurah: widget.onJumpToSurah,
                      ),
                      JuzList(
                        key: const ValueKey("juz"),
                        widget.onJumpToPage,
                        onJump: widget.onJumpToPage,
                        mushaf: widget.mushaf,
                        currentJuz: currentJuz,
                      ),
                    ],
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
