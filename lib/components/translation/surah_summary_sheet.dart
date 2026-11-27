import 'package:flutter/material.dart';

import '../../utils/app_palette.dart';
import '../../utils/surah_mapper.dart';
import '../../utils/surah_summary_manager.dart';

class SurahSummarySheet extends StatefulWidget {
  final SurahRange surah;
  final String fontSize;
  const SurahSummarySheet({
    super.key,
    required this.surah,
    required this.fontSize,
  });

  static const Map<String, ({double heading, double body})> _sizes = {
    'Small': (heading: 13.0, body: 13.0),
    'Medium': (heading: 14.0, body: 15.0),
    'Large': (heading: 16.0, body: 17.0),
  };

  @override
  State<SurahSummarySheet> createState() => _SurahSummarySheetState();
}

class _SurahSummarySheetState extends State<SurahSummarySheet> {
  bool _urdu = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final summary = SurahSummaryManager.get(widget.surah.surah, urdu: _urdu);
    final sizes = SurahSummarySheet._sizes[widget.fontSize]!;

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
                                padding: const EdgeInsets.only(
                                  top: 20,
                                  bottom: 6,
                                ),
                                child: Text(
                                  section.text,
                                  textDirection: _urdu
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                                  style: TextStyle(
                                    color: palette.accent,
                                    fontSize: sizes.heading,
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
                                        fontSize: sizes.body,
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
            color: active ? palette.onAccent : palette.muted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
