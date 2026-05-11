import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

class NavTile extends StatelessWidget {
  final int number;
  final String title;
  final String? englishTitle;
  final VoidCallback onTap;

  const NavTile({
    super.key,
    required this.number,
    required this.title,
    this.englishTitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border.withValues(alpha: .9)),
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
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: palette.surfaceMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
