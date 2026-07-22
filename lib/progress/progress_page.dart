import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

import 'reading_progress_store.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  ReadingProgress? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final progress = await ReadingProgressStore.load();
    if (mounted) setState(() => _progress = progress);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final progress = _progress;
    return Scaffold(
      backgroundColor: palette.scaffold,
      appBar: AppBar(
        backgroundColor: palette.scaffold,
        elevation: 0,
        title: Text(
          'Day Streak',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w800),
        ),
      ),
      body: progress == null
          ? Center(
              child: CircularProgressIndicator(
                color: palette.accent,
                strokeWidth: 2.5,
              ),
            )
          : Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: palette.accent.withValues(alpha: .22),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${progress.streak}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 52,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      progress.streak == 1 ? 'day streak' : 'day streak',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .88),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
