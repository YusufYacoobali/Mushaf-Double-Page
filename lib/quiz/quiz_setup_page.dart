import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/quran_arabic_style.dart';

import 'quiz_generator.dart';
import 'quiz_history_page.dart';
import 'quiz_history_store.dart';
import 'quiz_models.dart';
import 'quiz_play_page.dart';
import 'quiz_widgets.dart';

/// Entry screen for the memorization quiz: configure scope, length and mode.
class QuizSetupPage extends StatefulWidget {
  const QuizSetupPage({super.key});

  @override
  State<QuizSetupPage> createState() => _QuizSetupPageState();
}

class _QuizSetupPageState extends State<QuizSetupPage> {
  List<QuizRange> _ranges = [];
  int _questionCount = 10;
  int _answerLength = 5;
  QuizPromptMode _mode = QuizPromptMode.text;
  String _reciterId = quranReciters.first.id;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _restoreLastConfig();
  }

  Future<void> _restoreLastConfig() async {
    final last = await QuizHistoryStore.loadLastConfig();
    if (!mounted) return;
    setState(() {
      final c = last ?? QuizConfig.defaults;
      _ranges = [...c.ranges];
      _questionCount = c.questionCount;
      _answerLength = c.answerLength;
      _mode = c.promptMode;
      _reciterId = c.reciterId;
    });
  }

  QuizConfig get _config => QuizConfig(
    ranges: _ranges,
    questionCount: _questionCount,
    answerLength: _answerLength,
    promptMode: _mode,
    reciterId: _reciterId,
  );

  int get _eligibleCount =>
      _ranges.isEmpty ? 0 : QuizGenerator.eligiblePositions(_config).length;

  Future<void> _addRange() async {
    final range = await showModalBottomSheet<QuizRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddRangeSheet(),
    );
    if (range != null) setState(() => _ranges = [..._ranges, range]);
  }

  Future<void> _start() async {
    final eligible = QuizGenerator.eligiblePositions(_config);
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No verses in this scope')),
      );
      return;
    }

    setState(() => _starting = true);
    final prefs = await QuranArabicStyle.loadPrefs();
    final count = min(_questionCount, eligible.length);
    final questions = await QuizGenerator.generate(
      _config.copyWith(questionCount: count),
      script: prefs.script,
    );
    await QuizHistoryStore.saveLastConfig(_config);
    if (!mounted) return;
    setState(() => _starting = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuizPlayPage(
          config: _config,
          questions: questions,
          script: prefs.script,
          fontSize: prefs.fontSize,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: p.scaffold,
        elevation: 0,
        title: Text(
          'Memorization Quiz',
          style: TextStyle(color: p.text, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: Icon(Icons.history_rounded, color: p.text),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QuizHistoryPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
        children: [
          const QuizSectionLabel('Scope'),
          Text(
            'Pick surah or juz ranges to be tested on. Add as many as you like.',
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (_ranges.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _ranges.length; i++)
                  _RangeChip(
                    label: _ranges[i].label,
                    onRemove: () => setState(
                      () => _ranges = [..._ranges]..removeAt(i),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addRange,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add range'),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.accent,
              side: BorderSide(color: p.accent.withValues(alpha: .5)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (_ranges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '≈ $_eligibleCount verses available',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ],

          const SizedBox(height: 24),
          const QuizSectionLabel('Questions'),
          Wrap(
            spacing: 8,
            children: [
              for (final n in const [5, 10, 20, 30])
                QuizPill(
                  label: '$n',
                  selected: _questionCount == n,
                  onTap: () => setState(() => _questionCount = n),
                ),
            ],
          ),

          const SizedBox(height: 24),
          const QuizSectionLabel('Recall length'),
          Text(
            'How many ayahs to recall after the prompt.',
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final n in const [3, 5, 7, 10])
                QuizPill(
                  label: 'Next $n',
                  selected: _answerLength == n,
                  onTap: () => setState(() => _answerLength = n),
                ),
            ],
          ),

          const SizedBox(height: 24),
          const QuizSectionLabel('Prompt'),
          Wrap(
            spacing: 8,
            children: [
              QuizPill(
                label: 'Show ayah',
                selected: _mode == QuizPromptMode.text,
                onTap: () => setState(() => _mode = QuizPromptMode.text),
              ),
              QuizPill(
                label: 'Audio only',
                selected: _mode == QuizPromptMode.audio,
                onTap: () => setState(() => _mode = QuizPromptMode.audio),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const QuizSectionLabel('Reciter'),
          quizCard(
            p,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _reciterId,
                isExpanded: true,
                dropdownColor: p.surfaceRaised,
                borderRadius: BorderRadius.circular(13),
                iconEnabledColor: p.accent,
                style: TextStyle(
                  color: p.surfaceText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                items: [
                  for (final r in quranReciters)
                    DropdownMenuItem(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) => setState(() => _reciterId = v ?? _reciterId),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
        child: FilledButton(
          onPressed: (_ranges.isEmpty || _starting) ? null : _start,
          style: FilledButton.styleFrom(
            backgroundColor: p.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _starting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Start quiz',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _RangeChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 6, top: 7, bottom: 7),
      decoration: BoxDecoration(
        color: p.accentSoft,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: p.accent.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: p.accent,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(99),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.close_rounded, size: 16, color: p.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to add one surah or juz range.
class _AddRangeSheet extends StatefulWidget {
  const _AddRangeSheet();

  @override
  State<_AddRangeSheet> createState() => _AddRangeSheetState();
}

class _AddRangeSheetState extends State<_AddRangeSheet> {
  QuizRangeType _type = QuizRangeType.surah;
  int _from = 1;
  int _to = 1;

  int get _max => _type == QuizRangeType.surah ? 114 : 30;

  String _itemLabel(int n) {
    if (_type == QuizRangeType.juz) return 'Juz $n';
    return '$n. ${quranSurahs[n - 1].name}';
  }

  void _setType(QuizRangeType t) => setState(() {
    _type = t;
    _from = 1;
    _to = 1;
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.scaffold,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Add range',
            style: TextStyle(
              color: p.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              QuizPill(
                label: 'Surah',
                selected: _type == QuizRangeType.surah,
                onTap: () => _setType(QuizRangeType.surah),
              ),
              const SizedBox(width: 8),
              QuizPill(
                label: 'Juz',
                selected: _type == QuizRangeType.juz,
                onTap: () => _setType(QuizRangeType.juz),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: 'From',
                  value: _from,
                  max: _max,
                  itemLabel: _itemLabel,
                  onChanged: (v) => setState(() {
                    _from = v;
                    if (_to < _from) _to = _from;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: 'To',
                  value: _to,
                  min: _from,
                  max: _max,
                  itemLabel: _itemLabel,
                  onChanged: (v) => setState(() => _to = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(
                context,
                QuizRange(type: _type, from: _from, to: _to),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String Function(int) itemLabel;
  final ValueChanged<int> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.max,
    required this.itemLabel,
    required this.onChanged,
    this.min = 1,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: p.muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.surfaceRaised,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: p.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              dropdownColor: p.surfaceRaised,
              borderRadius: BorderRadius.circular(13),
              iconEnabledColor: p.accent,
              style: TextStyle(
                color: p.surfaceText,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              items: [
                for (var n = min; n <= max; n++)
                  DropdownMenuItem(
                    value: n,
                    child: Text(
                      itemLabel(n),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}
