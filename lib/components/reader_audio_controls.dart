import 'package:flutter/material.dart';
import '../utils/app_motion.dart';
import '../utils/app_palette.dart';

class ReaderAudioSelection {
  const ReaderAudioSelection({
    required this.reference,
    required this.bookmarked,
    required this.onBookmark,
    required this.onTranslate,
    this.onPlaySelected,
  });
  final String reference;
  final bool bookmarked;
  final VoidCallback onBookmark, onTranslate;
  final VoidCallback? onPlaySelected;
}

/// Compact playback controls that belong to the reader dock in either layout.
class ReaderAudioControls extends StatelessWidget {
  const ReaderAudioControls({
    super.key,
    required this.portrait,
    required this.palette,
    required this.title,
    required this.reference,
    required this.subtitle,
    required this.playing,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onSettings,
    this.selection,
  });
  final bool portrait, playing;
  final AppPalette palette;
  final String title, reference, subtitle;
  final VoidCallback onPrevious, onPlayPause, onNext, onSettings;
  final ReaderAudioSelection? selection;

  Widget _button(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool primary = false,
  }) => PressMotion(
    child: SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        tooltip: label,
        onPressed: onTap,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: primary ? palette.accentSoft : Colors.transparent,
        ),
        icon: Icon(
          icon,
          size: primary ? 23 : 19,
          color: primary ? palette.accent : palette.readerIcon,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selected = selection;
    final buttons = [
      _button('Previous ayah', Icons.skip_previous_rounded, onPrevious),
      _button(
        playing ? 'Pause' : 'Play',
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        onPlayPause,
        primary: true,
      ),
      _button('Next ayah', Icons.skip_next_rounded, onNext),
      if (selected == null)
        _button('Audio settings', Icons.tune_rounded, onSettings)
      else ...[
        if (selected.onPlaySelected != null)
          _button(
            'Play selected ayah',
            Icons.play_circle_outline_rounded,
            selected.onPlaySelected!,
          ),
        _button(
          selected.bookmarked ? 'Remove ayah bookmark' : 'Save ayah',
          selected.bookmarked
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          selected.onBookmark,
        ),
        _button(
          'Translate ayah',
          Icons.translate_rounded,
          selected.onTranslate,
        ),
      ],
    ];
    if (!portrait) {
      return SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected?.onPlaySelected != null)
              Text(
                'Selected',
                style: TextStyle(color: palette.readerIcon, fontSize: 8),
              ),
            Tooltip(
              message:
                  '$title\n$subtitle${selected == null ? '' : '\nAyah actions: ${selected.reference}'}',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    selected?.reference ?? reference,
                    style: TextStyle(
                      color: palette.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            ...buttons,
            const SizedBox(height: 6),
          ],
        ),
      );
    }
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 7, 4),
        child: Row(
          children: [
            Expanded(
              child: Tooltip(
                message:
                    '$title\n$subtitle${selected == null ? '' : '\nAyah actions: ${selected.reference}'}',
                child: InkWell(
                  onTap: onSettings,
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.readerIcon,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.readerIcon.withValues(alpha: .75),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            ...buttons,
          ],
        ),
      ),
    );
  }
}
