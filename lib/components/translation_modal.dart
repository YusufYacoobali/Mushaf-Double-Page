// lib/pages/translation_modal.dart

import 'package:flutter/material.dart';
import '../utils/translation_manager.dart';

class TranslationModal extends StatelessWidget {
  final int surahNumber;

  const TranslationModal({super.key, required this.surahNumber});

  @override
  Widget build(BuildContext context) {
    final surahTranslations = TranslationManager.getSurah(surahNumber);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return  Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              gradient: LinearGradient(
                colors: [Color(0xFFE8F5E9), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),  child: Column(

        children: [

        // 🔹 drag handle
        Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: Center(
        child: Container(
        width: 40,
        height: 5,
        decoration: BoxDecoration(
        color: Colors.grey.shade400,
        borderRadius: BorderRadius.circular(10),
        ),
        ),
        ),
        ),

        // 🔹 scrollable translations
        Expanded(

        child: Scrollbar(
            controller: scrollController,
            thumbVisibility: true,
            interactive: true,
            radius: const Radius.circular(10),
            thickness: 15,
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              itemCount: surahTranslations.length,
              itemBuilder: (context, index) {
                final ayahNumber = surahTranslations.keys.elementAt(index);
                final text = surahTranslations[ayahNumber];

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                    ],
                  ),
                );
              },
            ),
          ),
        )]));
      },
    );
  }

  static void show(BuildContext context, int surahNumber) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TranslationModal(surahNumber: surahNumber),
    );
  }
}