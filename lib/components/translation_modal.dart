// lib/pages/translation_modal.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/surah_mapper.dart';
import '../utils/translation_manager.dart';

class TranslationModal extends StatelessWidget {
  final List<SurahRange> surahs;

  const TranslationModal({super.key, required this.surahs});

  Future<void> _copyAyah(
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
          content: const Text('Ayah copied'),
          duration: const Duration(seconds: 1),
        ),
      );
    });
  }

  BorderRadius _rowRadius({required bool first, required bool last}) {
    const radius = Radius.circular(18);
    return BorderRadius.vertical(
      top: first ? radius : Radius.zero,
      bottom: last ? radius : Radius.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Flatten surah headers + ayahs into one list for lazy building
    final List<dynamic> items = [];

    for (final surah in surahs) {
      items.add(surah); // header

      final ayahs = TranslationManager.getSurah(surah.surah);

      for (final entry in ayahs.entries) {
        items.add({"ayah": entry.key, "text": entry.value});
      }
    }

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
              /// drag handle
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

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: palette.accentSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.chat_outlined,
                        color: palette.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Translation',
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Scrollbar(
                  controller: scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  radius: const Radius.circular(10),
                  thickness: 6,
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];

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
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                            ],
                          ),
                        );
                      }

                      final ayahNumber = item["ayah"] as int;
                      final text = (item["text"] as String?) ?? '';
                      final previousStartsSection =
                          index == 0 || items[index - 1] is SurahRange;
                      final nextStartsSection =
                          index == items.length - 1 ||
                          items[index + 1] is SurahRange;

                      return Container(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: _rowRadius(
                            first: previousStartsSection,
                            last: nextStartsSection,
                          ),
                          border: Border(
                            left: BorderSide(color: palette.border),
                            right: BorderSide(color: palette.border),
                            top: previousStartsSection
                                ? BorderSide(color: palette.border)
                                : BorderSide.none,
                            bottom: BorderSide(color: palette.border),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 28,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: palette.accentSoft,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: palette.accent.withValues(
                                      alpha: .18,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  ayahNumber.toString(),
                                  style: TextStyle(
                                    color: palette.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SelectableText(
                                  text,
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.42,
                                    color: palette.surfaceText,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: palette.surfaceMuted,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                tooltip: 'Ayah actions',
                                color: palette.surfaceRaised,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                onSelected: (value) {
                                  if (value == 'copy') {
                                    _copyAyah(context, palette, text);
                                    return;
                                  }

                                  SharePlus.instance.share(
                                    ShareParams(text: text),
                                  );
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

  static void show(BuildContext context, List<SurahRange> surahs) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TranslationModal(surahs: surahs),
    );
  }
}
