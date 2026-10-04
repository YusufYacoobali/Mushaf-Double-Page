import 'package:flutter/material.dart';
import '../utils/app_palette.dart';
import '../utils/app_motion.dart';

class AyahActionBar extends StatelessWidget {
  const AyahActionBar({
    super.key,
    required this.title,
    this.vertical = false,
    this.reference,
    required this.bookmarked,
    required this.palette,
    required this.onPlay,
    required this.onBookmark,
    required this.onTranslate,
    required this.onClose,
  });
  final String title;
  final bool vertical;
  final String? reference;
  final bool bookmarked;
  final AppPalette palette;
  final VoidCallback onPlay;
  final VoidCallback onBookmark;
  final VoidCallback onTranslate;
  final VoidCallback onClose;

  Widget _action(String label, IconData icon, VoidCallback onTap) =>
      PressMotion(
        child: IconButton(
          tooltip: label,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          icon: Icon(icon, color: palette.readerIcon, size: 18),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final actions = [
      _action('Play ayah', Icons.play_arrow_rounded, onPlay),
      _action(
        bookmarked ? 'Remove ayah bookmark' : 'Save ayah',
        bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        onBookmark,
      ),
      _action('Translate ayah', Icons.translate_rounded, onTranslate),
      _action('Clear ayah selection', Icons.close_rounded, onClose),
    ];
    if (vertical) {
      return SizedBox(
        width: 38,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: title,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(3, 12, 3, 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    reference ?? title,
                    style: TextStyle(
                      color: palette.readerIcon,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            ...actions,
            const SizedBox(height: 4),
          ],
        ),
      );
    }
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.readerIcon,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
