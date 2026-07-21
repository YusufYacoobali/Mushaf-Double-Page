import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';

import 'quiz_history_store.dart';
import 'quiz_models.dart';
import 'quiz_widgets.dart';

class QuizHistoryPage extends StatefulWidget {
  const QuizHistoryPage({super.key});

  @override
  State<QuizHistoryPage> createState() => _QuizHistoryPageState();
}

class _QuizHistoryPageState extends State<QuizHistoryPage> {
  List<QuizHistoryEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await QuizHistoryStore.load();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  Future<void> _clear() async {
    await QuizHistoryStore.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final entries = _entries;
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: p.scaffold,
        elevation: 0,
        title: Text(
          'Quiz history',
          style: TextStyle(color: p.text, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (entries != null && entries.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: Icon(Icons.delete_outline_rounded, color: p.text),
              onPressed: _clear,
            ),
        ],
      ),
      body: entries == null
          ? Center(
              child: CircularProgressIndicator(color: p.accent, strokeWidth: 2.5),
            )
          : entries.isEmpty
          ? Center(
              child: Text(
                'No quizzes yet',
                style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _HistoryTile(entry: entries[i]),
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final QuizHistoryEntry entry;
  const _HistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final pct = entry.total == 0
        ? 0
        : (entry.correct * 100 / entry.total).round();
    final mode = entry.promptMode == QuizPromptMode.audio ? 'Audio' : 'Text';
    return quizCard(
      p,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '$pct%',
              style: TextStyle(
                color: p.accent,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.scopeLabel.isEmpty ? 'Quiz' : entry.scopeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.surfaceText,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.correct}/${entry.total} correct  ·  next ${entry.answerLength}  ·  $mode',
                  style: TextStyle(color: p.surfaceMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(entry.date),
                  style: TextStyle(color: p.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}  ${two(local.hour)}:${two(local.minute)}';
  }
}
