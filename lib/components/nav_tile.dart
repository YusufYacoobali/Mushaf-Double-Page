import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

class NavTile extends StatelessWidget {
  final int number;
  final String title;
  final String? englishTitle;
  final VoidCallback onTap;
  final bool selected;

  const NavTile({
    super.key,
    required this.number,
    required this.title,
    this.englishTitle,
    required this.onTap,
    this.selected = false,
  });

  static double extentFor(
    BuildContext context,
    double width,
    String title, {
    String? englishTitle,
  }) {
    final theme = Theme.of(context);
    // Row padding/border, number badge, gap and trailing icon.
    final textWidth = (width - 108).clamp(1.0, double.infinity);
    double height(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: textWidth);
      final result = painter.height;
      painter.dispose();
      return result;
    }

    final textHeight =
        height(
          title,
          theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        ) +
        (englishTitle == null
            ? 0
            : height(englishTitle, theme.textTheme.bodySmall));
    return 30 + (textHeight > 42 ? textHeight : 42);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);

    return Semantics(
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: selected ? palette.accentSoft : palette.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? palette.accent
                      : palette.border.withValues(alpha: .9),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: palette.accentSoft,
                    ),
                    child: Text(
                      number.toString(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: palette.accent,
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: palette.surfaceText,
                          ),
                        ),

                        if (englishTitle != null)
                          Text(
                            englishTitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: palette.surfaceMuted,
                            ),
                          ),
                      ],
                    ),
                  ),

                  Icon(
                    selected
                        ? Icons.my_location_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: selected ? palette.accent : palette.surfaceMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
