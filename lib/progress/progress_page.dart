import 'package:flutter/material.dart';
import 'package:mushaf_two_page/logic/storage_manager.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/surah_mapper.dart';

import 'reading_progress_store.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  ReadingProgress? _progress;
  String _mushaf = 'indopak_tajweed';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mushaf = await StorageManager.getMushaf();
    final ranges = getSurahRanges(mushaf);
    final first = ranges.firstWhere((r) => r.surah == 1).start;
    final last = ranges.last.end;
    final progress = await ReadingProgressStore.load(
      mushaf: mushaf,
      firstContent: first,
      lastContent: last,
    );
    if (!mounted) return;
    setState(() {
      _mushaf = mushaf;
      _progress = progress;
    });
  }

  Future<void> _resetKhatm() async {
    await ReadingProgressStore.resetKhatm(_mushaf);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final progress = _progress;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: p.scaffold,
        elevation: 0,
        title: Text(
          'Progress',
          style: TextStyle(color: p.text, fontWeight: FontWeight.w800),
        ),
      ),
      body: progress == null
          ? Center(
              child: CircularProgressIndicator(color: p.accent, strokeWidth: 2.5),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.local_fire_department_rounded,
                        value: '${progress.streak}',
                        label: progress.streak == 1 ? 'day streak' : 'day streak',
                        accent: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.emoji_events_rounded,
                        value: '${progress.khatmCount}',
                        label: progress.khatmCount == 1
                            ? 'khatm done'
                            : 'khatms done',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _KhatmCard(progress: progress, onReset: _resetKhatm),
                const SizedBox(height: 12),
                _StatRow(
                  label: 'Longest streak',
                  value: '${progress.longestStreak} days',
                ),
                _StatRow(
                  label: 'Pages read this khatm',
                  value: '${progress.readPages} / ${progress.totalPages}',
                ),
              ],
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool accent;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: accent ? p.accent : p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent ? p.accent : p.border.withValues(alpha: .7),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: accent ? Colors.white : p.accent, size: 30),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: accent ? Colors.white : p.surfaceText,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: accent ? Colors.white.withValues(alpha: .85) : p.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _KhatmCard extends StatelessWidget {
  final ReadingProgress progress;
  final VoidCallback onReset;

  const _KhatmCard({required this.progress, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border.withValues(alpha: .7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Current khatm',
                style: TextStyle(
                  color: p.surfaceText,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text(
                '${progress.khatmPercent}%',
                style: TextStyle(
                  color: p.accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress.khatmFraction,
              minHeight: 10,
              backgroundColor: p.accent.withValues(alpha: .12),
              color: p.accent,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReset,
              icon: Icon(Icons.refresh_rounded, size: 18, color: p.muted),
              label: Text('Reset', style: TextStyle(color: p.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: p.surfaceText,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
