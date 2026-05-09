// lib/pages/translation_modal.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/surah_mapper.dart';
import '../utils/translation_manager.dart';

class TranslationModal extends StatelessWidget {
  final List<SurahRange> surahs;

  const TranslationModal({super.key, required this.surahs});

  @override
  Widget build(BuildContext context) {
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
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            gradient: LinearGradient(
              colors: [Color(0xFFE8F5E9), Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
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
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              Expanded(
                child: Scrollbar(
                  controller: scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  radius: const Radius.circular(10),
                  thickness: 15,

                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];

                      /// Surah header
                      if (item is SurahRange) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12, top: 10),
                          child: Column(
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF025C32),
                                ),
                              ),
                              Text(
                                item.english,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      /// Ayah card
                      final ayahNumber = item["ayah"];
                      final text = item["text"];

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF025C32),
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 4,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),

                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: const Color(0xFF025C32),
                              child: Text(
                                ayahNumber.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: SelectableText(
                                text ?? '',
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                  color: Color(0xFF1B5E20),
                                ),
                              ),
                            ),

                            /// Copy + Share buttons
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: text ?? ''),
                                    );

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text("Ayah copied"),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),

                                IconButton(
                                  icon: const Icon(Icons.share, size: 18),
                                  onPressed: () {
                                    SharePlus.instance.share(
                                      ShareParams(text: text ?? ''),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
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
