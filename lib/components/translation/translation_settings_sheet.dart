import 'package:flutter/material.dart';

import '../../utils/app_palette.dart';
import '../../utils/tafseer_manager.dart';
import '../../utils/translation_manager.dart';
import '../../utils/translation_preferences.dart';

class TranslationSettingsSheet extends StatefulWidget {
  const TranslationSettingsSheet({
    super.key,
    required this.initial,
    required this.onApply,
  });
  final TranslationPreferencesData initial;
  final ValueChanged<TranslationPreferencesData> onApply;
  @override
  State<TranslationSettingsSheet> createState() =>
      _TranslationSettingsSheetState();
}

class _TranslationSettingsSheetState extends State<TranslationSettingsSheet> {
  late final _translations = List.of(widget.initial.translations);
  late final _tafseers = List.of(widget.initial.tafseers);
  late bool _showArabic = widget.initial.showArabic;
  late String _fontSize = widget.initial.fontSize;
  late String _arabicScript = widget.initial.arabicScript;

  void persistSourceSelections() {
    TranslationPreferences.saveSourceSelections(
      translations: List<String>.from(_translations),
      tafseers: List<String>.from(_tafseers),
    ).ignore();
  }

  void toggleTrans(String src) {
    setState(() {
      if (_translations.contains(src)) {
        if (_translations.length > 1) _translations.remove(src);
      } else {
        _translations.add(src);
      }
    });
    persistSourceSelections();
  }

  void toggleTafseer(String src) {
    setState(() {
      _tafseers.contains(src) ? _tafseers.remove(src) : _tafseers.add(src);
    });
    persistSourceSelections();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: palette.scaffold,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
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
                      Navigator.pop(context);
                      widget.onApply(
                        TranslationPreferencesData(
                          translations: _translations,
                          tafseers: _tafseers,
                          showArabic: _showArabic,
                          fontSize: _fontSize,
                          arabicScript: _arabicScript,
                        ),
                      );
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
                      child: Text(
                        'Done',
                        style: TextStyle(
                          color: palette.onAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionLabel(palette: palette, label: 'Display'),
              const SizedBox(height: 6),
              _CheckTile(
                palette: palette,
                label: 'Show Arabic text',
                checked: _showArabic,
                onTap: () => setState(() => _showArabic = !_showArabic),
              ),
              if (_showArabic) ...[
                const SizedBox(height: 12),
                _SectionLabel(palette: palette, label: 'Arabic Script'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final script in [
                      ('uthmani', 'Uthmani'),
                      ('indopak', 'Indo-Pak'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _arabicScript = script.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _arabicScript == script.$1
                                  ? palette.accent
                                  : palette.surface,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: _arabicScript == script.$1
                                    ? palette.accent
                                    : palette.border,
                              ),
                            ),
                            child: Text(
                              script.$2,
                              style: TextStyle(
                                color: _arabicScript == script.$1
                                    ? palette.onAccent
                                    : palette.text,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              _SectionLabel(palette: palette, label: 'Font Size'),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final size in ['Small', 'Medium', 'Large'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _fontSize = size),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _fontSize == size
                                ? palette.accent
                                : palette.surface,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: _fontSize == size
                                  ? palette.accent
                                  : palette.border,
                            ),
                          ),
                          child: Text(
                            size,
                            style: TextStyle(
                              color: _fontSize == size
                                  ? palette.onAccent
                                  : palette.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionLabel(palette: palette, label: 'Translation'),
              const SizedBox(height: 6),
              ...TranslationManager.sources.keys.map(
                (src) => _CheckTile(
                  palette: palette,
                  label: src,
                  checked: _translations.contains(src),
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
                  checked: _tafseers.contains(src),
                  onTap: () => toggleTafseer(src),
                ),
              ),
            ],
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
