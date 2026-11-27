import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../progress/journey_tracking.dart';
import '../../utils/app_motion.dart';
import '../../utils/app_palette.dart';
import '../../utils/quran_arabic_style.dart';
import '../../utils/translation_preferences.dart';
import 'translation_content.dart';

class TranslationAyahRow extends StatelessWidget {
  const TranslationAyahRow({
    super.key,
    required this.item,
    required this.preferences,
    required this.first,
    required this.last,
    required this.isFocused,
    required this.isBookmarked,
    required this.translationsSeen,
    required this.collapsedTranslations,
    required this.collapsedTafseers,
    required this.onBookmark,
    required this.onToggleTranslation,
    required this.onToggleTafseer,
  });
  final TranslationAyah item;
  final TranslationPreferencesData preferences;
  final bool first, last, isFocused, isBookmarked;
  final Set<String> translationsSeen, collapsedTranslations, collapsedTafseers;
  final VoidCallback onBookmark;
  final ValueChanged<String> onToggleTranslation, onToggleTafseer;
  static const Map<String, ({double arabic, double trans, double tafseer})>
  _fontSizeMap = {
    'Small': (arabic: 18.0, trans: 13.0, tafseer: 13.0),
    'Medium': (arabic: 22.0, trans: 16.0, tafseer: 16.0),
    'Large': (arabic: 26.0, trans: 19.0, tafseer: 19.0),
  };
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

  static final _arabicRunRe = RegExp(r'[؀-ۿﭐ-﷿ﹰ-﻿]{2,}(?:\s+[؀-ۿﭐ-﷿ﹰ-﻿]{2,})*');

  List<Widget> _tafseerParaWidgets(String para, double fontSize, Color color) {
    final widgets = <Widget>[];
    int last = 0;
    for (final m in _arabicRunRe.allMatches(para)) {
      final before = para.substring(last, m.start).trim();
      if (before.isNotEmpty) {
        widgets.add(_tafseerRun(before, fontSize, color, rtl: false));
      }
      final arabic = m.group(0)!.trim();
      if (arabic.isNotEmpty) {
        widgets.add(_tafseerRun(arabic, fontSize, color, rtl: true));
      }
      last = m.end;
    }
    final tail = para.substring(last).trim();
    if (tail.isNotEmpty) {
      widgets.add(_tafseerRun(tail, fontSize, color, rtl: false));
    }
    if (widgets.isEmpty) {
      widgets.add(_tafseerRun(para, fontSize, color, rtl: false));
    }
    return widgets;
  }

  Widget _tafseerRun(
    String text,
    double fontSize,
    Color color, {
    required bool rtl,
  }) {
    return SelectableText(
      text,
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        fontSize: rtl ? fontSize + 2 : fontSize,
        height: 1.5,
        color: color,
        fontFamily: rtl ? 'NotoNaskh' : null,
      ),
    );
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
    final surahNum = item.surah, ayahNumber = item.ayah;
    final trans = item.translations, tafseer = item.tafseers;
    final arabic = item.arabic;
    final rowBorder = isFocused ? palette.accent : palette.border;

    return Container(
      decoration: BoxDecoration(
        color: isFocused ? palette.accentSoft : palette.surface,
        borderRadius: _rowRadius(first: first, last: last),
        border: Border(
          left: BorderSide(color: rowBorder, width: isFocused ? 2 : 1),
          right: BorderSide(color: rowBorder, width: isFocused ? 2 : 1),
          top: first ? BorderSide(color: rowBorder) : BorderSide.none,
          bottom: BorderSide(color: rowBorder),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: palette.accent.withValues(alpha: .18),
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
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBookmark,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      isBookmarked
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: isBookmarked
                          ? palette.accent
                          : palette.surfaceMuted,
                      size: 19,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  popUpAnimationStyle: AppMotion.style(context),
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: palette.surfaceMuted,
                    size: 18,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Actions',
                  color: palette.surfaceRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (value) {
                    if (value == 'copy') {
                      _copyText(context, palette, item.textForSharing);
                    } else {
                      SharePlus.instance.share(
                        ShareParams(text: item.textForSharing),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Arabic text
                if (preferences.showArabic && arabic.isNotEmpty) ...[
                  SizedBox(
                    width: double.infinity,
                    child: Text(
                      arabic,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: QuranArabicStyle.ayah(
                        script: preferences.arabicScript,
                        fontSize: preferences.fontSize,
                        color: palette.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // Translation blocks
                ...preferences.translations.asMap().entries.map((e) {
                  final src = e.value;
                  final text = trans[src] ?? '';
                  final srcKey = '$surahNum:$ayahNumber:$src';
                  final srcCollapsed = collapsedTranslations.contains(srcKey);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (e.key > 0) Divider(height: 16, color: palette.border),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onToggleTranslation(srcKey),
                        child: Row(
                          children: [
                            Text(
                              src,
                              style: TextStyle(
                                color: palette.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              srcCollapsed
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.keyboard_arrow_up_rounded,
                              size: 16,
                              color: palette.accent,
                            ),
                          ],
                        ),
                      ),
                      if (!srcCollapsed && text.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        TranslationExposure(
                          verse: '$surahNum:$ayahNumber',
                          seen: translationsSeen,
                          child: SelectableText(
                            text,
                            style: TextStyle(
                              fontSize:
                                  _fontSizeMap[preferences.fontSize]!.trans,
                              height: 1.45,
                              color: palette.surfaceText,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                }),

                // Tafseer blocks
                if (preferences.tafseers.isNotEmpty &&
                    preferences.tafseers.any(
                      (s) => (tafseer[s] ?? '').isNotEmpty,
                    )) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: palette.scaffold,
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: palette.accent.withValues(alpha: .2),
                          width: 2,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: preferences.tafseers
                          .asMap()
                          .entries
                          .map<Widget>((e) {
                            final src = e.value;
                            final text = tafseer[src] ?? '';
                            if (text.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            final srcKey = '$surahNum:$ayahNumber:$src';
                            final srcCollapsed = collapsedTafseers.contains(
                              srcKey,
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (e.key > 0)
                                  Divider(height: 16, color: palette.border),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => onToggleTafseer(srcKey),
                                  child: Row(
                                    children: [
                                      Text(
                                        src,
                                        style: TextStyle(
                                          color: palette.muted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        srcCollapsed
                                            ? Icons.keyboard_arrow_down_rounded
                                            : Icons.keyboard_arrow_up_rounded,
                                        size: 16,
                                        color: palette.muted,
                                      ),
                                    ],
                                  ),
                                ),
                                if (!srcCollapsed) ...[
                                  const SizedBox(height: 4),
                                  for (final para
                                      in text
                                          .split('\n\n')
                                          .map((p) => p.trim())
                                          .where((p) => p.isNotEmpty))
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 36,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: _tafseerParaWidgets(
                                          para,
                                          _fontSizeMap[preferences.fontSize]!
                                              .tafseer,
                                          palette.text.withValues(alpha: .95),
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            );
                          })
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
