import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/surah_mapper.dart';
import '../utils/translation_manager.dart';
import '../utils/tafseer_manager.dart';
import '../utils/surah_summary_manager.dart';

class TranslationModal extends StatefulWidget {
  final List<SurahRange> surahs;

  const TranslationModal({super.key, required this.surahs});

  static void show(BuildContext context, List<SurahRange> surahs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TranslationModal(surahs: surahs),
    );
  }

  @override
  State<TranslationModal> createState() => _TranslationModalState();
}

class _TranslationModalState extends State<TranslationModal> {
  final List<String> _selectedTrans = ['Saheeh International'];
  final List<String> _selectedTafseer = ['Tafseer Ibn Kathir'];
  bool _loading = true;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    for (final src in _selectedTrans) {
      await TranslationManager.loadSource(src);
    }

    final items = <dynamic>[];

    for (final surah in widget.surahs) {
      items.add(surah);

      final transData = <String, Map<int, String>>{};
      for (final src in _selectedTrans) {
        transData[src] = TranslationManager.getSurah(surah.surah, source: src);
      }

      final tafseerData = <String, Map<int, String>>{};
      if (_selectedTafseer.isNotEmpty) {
        for (final src in _selectedTafseer) {
          tafseerData[src] = await TafseerManager.getSurah(surah.surah, src);
        }
      }

      final ayahs = (transData[_selectedTrans.first] ?? {}).keys.toList()
        ..sort();

      for (final ayah in ayahs) {
        final trans = <String, String>{};
        for (final src in _selectedTrans) {
          trans[src] = transData[src]?[ayah] ?? '';
        }
        final tafseer = <String, String>{};
        for (final src in _selectedTafseer) {
          tafseer[src] = tafseerData[src]?[ayah] ?? '';
        }
        items.add({'ayah': ayah, 'trans': trans, 'tafseer': tafseer});
      }
    }

    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _showSummary(BuildContext outerContext, SurahRange surah) {
    showModalBottomSheet(
      context: outerContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SummarySheet(surah: surah),
    );
  }

  void _showSettings() {
    final tempTrans = List<String>.from(_selectedTrans);
    final tempTafseer = List<String>.from(_selectedTafseer);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final palette = AppPalette.of(context);
        return StatefulBuilder(
          builder: (ctx, setS) {
            void toggleTrans(String src) => setS(() {
              if (tempTrans.contains(src)) {
                if (tempTrans.length > 1) tempTrans.remove(src);
              } else {
                tempTrans.add(src);
              }
            });
            void toggleTafseer(String src) => setS(() {
              tempTafseer.contains(src)
                  ? tempTafseer.remove(src)
                  : tempTafseer.add(src);
            });

            return Container(
              decoration: BoxDecoration(
                color: palette.scaffold,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: palette.border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Sources',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _selectedTrans
                              ..clear()
                              ..addAll(tempTrans);
                            _selectedTafseer
                              ..clear()
                              ..addAll(tempTafseer);
                          });
                          _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: palette.accent,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(palette: palette, label: 'Translation'),
                  const SizedBox(height: 6),
                  ...TranslationManager.sources.keys.map(
                    (src) => _CheckTile(
                      palette: palette,
                      label: src,
                      checked: tempTrans.contains(src),
                      onTap: () => toggleTrans(src),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel(palette: palette, label: 'Tafseer'),
                  const SizedBox(height: 6),
                  ...TafseerManager.sources.keys.map(
                    (src) => _CheckTile(
                      palette: palette,
                      label: src,
                      checked: tempTafseer.contains(src),
                      onTap: () => toggleTafseer(src),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _copyText(
    BuildContext context,
    AppPalette palette,
    String text,
  ) {
    return Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: palette.accent,
          behavior: SnackBarBehavior.floating,
          content: const Text('Copied'),
          duration: const Duration(seconds: 1),
        ),
      );
    });
  }

  BorderRadius _rowRadius({required bool first, required bool last}) {
    const r = Radius.circular(18);
    return BorderRadius.vertical(
      top: first ? r : Radius.zero,
      bottom: last ? r : Radius.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            color: palette.scaffold,
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Header row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 8, 10),
                child: Row(
                  children: [
                    Text(
                      'Translation',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _showSettings,
                      icon: Icon(
                        Icons.tune_rounded,
                        color: palette.muted,
                        size: 22,
                      ),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: palette.accent,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        interactive: true,
                        radius: const Radius.circular(10),
                        thickness: 6,
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 22),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];

                            if (item is SurahRange) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: palette.accent,
                                        borderRadius:
                                            BorderRadius.circular(99),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            style: TextStyle(
                                              color: palette.text,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            item.english,
                                            style: TextStyle(
                                              color: palette.muted,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => _showSummary(context, item),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: palette.accentSoft,
                                          borderRadius: BorderRadius.circular(99),
                                          border: Border.all(
                                            color: palette.accent.withValues(alpha: .2),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.info_outline_rounded,
                                              size: 13,
                                              color: palette.accent,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Summary',
                                              style: TextStyle(
                                                color: palette.accent,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final ayahNumber = item['ayah'] as int;
                            final trans =
                                item['trans'] as Map<String, String>;
                            final tafseer =
                                item['tafseer'] as Map<String, String>;
                            final prevIsHeader =
                                index == 0 ||
                                _items[index - 1] is SurahRange;
                            final nextIsHeader =
                                index == _items.length - 1 ||
                                _items[index + 1] is SurahRange;

                            final allText = [
                              ...trans.values,
                              if (_selectedTafseer.isNotEmpty) ...tafseer.values,
                            ].join('\n\n');

                            return Container(
                              decoration: BoxDecoration(
                                color: palette.surface,
                                borderRadius: _rowRadius(
                                  first: prevIsHeader,
                                  last: nextIsHeader,
                                ),
                                border: Border(
                                  left: BorderSide(color: palette.border),
                                  right: BorderSide(color: palette.border),
                                  top: prevIsHeader
                                      ? BorderSide(color: palette.border)
                                      : BorderSide.none,
                                  bottom: BorderSide(color: palette.border),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    10, 6, 4, 8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // Top row: ayah badge + menu
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: palette.accentSoft,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            border: Border.all(
                                              color: palette.accent
                                                  .withValues(alpha: .18),
                                            ),
                                          ),
                                          child: Text(
                                            ayahNumber.toString(),
                                            style: TextStyle(
                                              color: palette.accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              height: 1,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        PopupMenuButton<String>(
                                          icon: Icon(
                                            Icons.more_vert_rounded,
                                            color: palette.surfaceMuted,
                                            size: 18,
                                          ),
                                          padding: EdgeInsets.zero,
                                          tooltip: 'Actions',
                                          color: palette.surfaceRaised,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          onSelected: (value) {
                                            if (value == 'copy') {
                                              _copyText(
                                                  context, palette, allText);
                                            } else {
                                              SharePlus.instance.share(
                                                ShareParams(text: allText),
                                              );
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'copy',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.copy_rounded,
                                                    color: palette.accent,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  const Text('Copy'),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'share',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.ios_share_rounded,
                                                    color: palette.accent,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  const Text('Share'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),

                                    // Text content (full width)
                                    Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Translation blocks
                                          ..._selectedTrans
                                              .asMap()
                                              .entries
                                              .map((e) {
                                            final src = e.value;
                                            final text = trans[src] ?? '';
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (e.key > 0)
                                                  Divider(
                                                    height: 20,
                                                    color: palette.border,
                                                  ),
                                                if (_selectedTrans.length >
                                                    1) ...[
                                                  Text(
                                                    src,
                                                    style: TextStyle(
                                                      color: palette.accent,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                ],
                                                SelectableText(
                                                  text,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    height: 1.45,
                                                    color:
                                                        palette.surfaceText,
                                                  ),
                                                ),
                                              ],
                                            );
                                          }),

                                          // Tafseer blocks
                                          if (_selectedTafseer.isNotEmpty &&
                                              _selectedTafseer
                                                  .any((s) =>
                                                      (tafseer[s] ?? '')
                                                          .isNotEmpty)) ...[
                                            const SizedBox(height: 6),
                                            Container(
                                              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                                              decoration: BoxDecoration(
                                                color: palette.scaffold,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        8),
                                                border: Border(
                                                  left: BorderSide(
                                                    color: palette.accent
                                                        .withValues(alpha: .2),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: _selectedTafseer
                                                    .asMap()
                                                    .entries
                                                    .map((e) {
                                                  final src = e.value;
                                                  final text =
                                                      tafseer[src] ?? '';
                                                  if (text.isEmpty) {
                                                    return const SizedBox
                                                        .shrink();
                                                  }
                                                  return Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      if (e.key > 0)
                                                        Divider(
                                                          height: 20,
                                                          color:
                                                              palette.border,
                                                        ),
                                                      Text(
                                                        src,
                                                        style: TextStyle(
                                                          color:
                                                              palette.muted,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          letterSpacing: 0.3,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 4),
                                                      SelectableText(
                                                        text,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          height: 1.5,
                                                          color: palette.text
                                                              .withValues(alpha: .95),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                }).toList(),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummarySheet extends StatefulWidget {
  final SurahRange surah;
  const _SummarySheet({required this.surah});

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  bool _urdu = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final summary = SurahSummaryManager.get(widget.surah.surah, urdu: _urdu);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.scaffold,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Header: surah name + language toggle
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.surah.name,
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Summary',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Language pill toggle
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LangSegment(
                            palette: palette,
                            label: 'English',
                            active: !_urdu,
                            onTap: () => setState(() => _urdu = false),
                          ),
                          _LangSegment(
                            palette: palette,
                            label: 'اردو',
                            active: _urdu,
                            onTap: () => setState(() => _urdu = true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: palette.border),

              // Content
              Expanded(
                child: summary == null
                    ? Center(
                        child: Text(
                          'No summary available',
                          style: TextStyle(color: palette.muted),
                        ),
                      )
                    : Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        radius: const Radius.circular(10),
                        thickness: 6,
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          itemCount: summary.sections.length,
                          itemBuilder: (context, i) {
                            final section = summary.sections[i];
                            if (section.isHeading) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 20, bottom: 6),
                                child: Text(
                                  section.text,
                                  textDirection: _urdu
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                                  style: TextStyle(
                                    color: palette.accent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              );
                            }
                            final paras = section.text
                                .split('\n\n')
                                .map((p) => p.trim())
                                .where((p) => p.isNotEmpty)
                                .toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final para in paras)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 36),
                                    child: Text(
                                      para,
                                      textDirection: _urdu
                                          ? TextDirection.rtl
                                          : TextDirection.ltr,
                                      style: TextStyle(
                                        color: palette.text,
                                        fontSize: 15,
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LangSegment extends StatelessWidget {
  final AppPalette palette;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LangSegment({
    required this.palette,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? palette.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : palette.muted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final AppPalette palette;
  final String label;

  const _SectionLabel({required this.palette, required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: palette.muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final AppPalette palette;
  final String label;
  final bool checked;
  final VoidCallback onTap;

  const _CheckTile({
    required this.palette,
    required this.label,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: checked,
                onChanged: (_) => onTap(),
                activeColor: palette.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                side: BorderSide(color: palette.border, width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: palette.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
