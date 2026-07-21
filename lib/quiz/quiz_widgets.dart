import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

class QuizSectionLabel extends StatelessWidget {
  final String text;
  const QuizSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: p.muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// A pill-shaped selectable chip matching the translation settings style.
class QuizPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const QuizPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? p.accent : p.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? p.accent : p.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : p.text,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

Widget quizCard(AppPalette p, {required Widget child, EdgeInsets? padding}) {
  return Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: p.border.withValues(alpha: .7)),
    ),
    child: child,
  );
}
