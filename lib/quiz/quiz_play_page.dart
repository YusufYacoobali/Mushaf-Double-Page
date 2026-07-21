import 'package:flutter/material.dart';
import 'package:mushaf_two_page/logic/quran_audio_controller.dart';
import 'package:mushaf_two_page/models/quran_audio.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/quran_arabic_style.dart';

import 'quiz_history_store.dart';
import 'quiz_models.dart';
import 'quiz_widgets.dart';

/// Runs a generated quiz: shows each prompt, reveals the answer via hints, and
/// records a self-graded score that is saved to history at the end.
class QuizPlayPage extends StatefulWidget {
  final QuizConfig config;
  final List<QuizQuestion> questions;
  final String script;
  final String fontSize;

  const QuizPlayPage({
    super.key,
    required this.config,
    required this.questions,
    required this.script,
    required this.fontSize,
  });

  @override
  State<QuizPlayPage> createState() => _QuizPlayPageState();
}

class _QuizPlayPageState extends State<QuizPlayPage> {
  int _index = 0;
  int _correct = 0;
  int _hintCount = 0; // answer ayahs revealed via hints
  bool _answerShown = false;
  bool _finished = false;
  bool _savedHistory = false;

  QuizQuestion get _q => widget.questions[_index];
  int get _total => widget.questions.length;

  Reciter get _reciter => quranReciters.firstWhere(
    (r) => r.id == widget.config.reciterId,
    orElse: () => quranReciters.first,
  );

  @override
  void dispose() {
    QuranAudioController.instance.stop();
    super.dispose();
  }

  void _playRange(int from, int to) {
    QuranAudioController.instance.playPlan(
      AudioPlaybackPlan(
        reciter: _reciter,
        surah: _q.surah,
        fromAyah: from,
        toAyah: to,
        repeatCount: 1,
        repeatMode: AudioRepeatMode.range,
        sourceMode: AudioSourceMode.range,
      ),
    );
  }

  void _hint() {
    if (_answerShown) return;
    setState(() {
      if (_hintCount < _q.answerAyahs.length) _hintCount++;
    });
  }

  void _grade(bool correct) {
    QuranAudioController.instance.stop();
    if (correct) _correct++;
    if (_index + 1 >= _total) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _hintCount = 0;
      _answerShown = false;
    });
  }

  Future<void> _finish() async {
    if (!_savedHistory) {
      _savedHistory = true;
      await QuizHistoryStore.add(
        QuizHistoryEntry(
          date: DateTime.now(),
          scopeLabel: widget.config.scopeLabel,
          total: _total,
          correct: _correct,
          answerLength: widget.config.answerLength,
          promptMode: widget.config.promptMode,
        ),
      );
    }
    if (mounted) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (widget.questions.isEmpty) {
      return Scaffold(
        backgroundColor: p.scaffold,
        appBar: AppBar(backgroundColor: p.scaffold, elevation: 0),
        body: Center(
          child: Text(
            'No verses in this scope',
            style: TextStyle(color: p.muted),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.scaffold,
      appBar: AppBar(
        backgroundColor: p.scaffold,
        elevation: 0,
        title: Text(
          _finished ? 'Result' : 'Question ${_index + 1} of $_total',
          style: TextStyle(color: p.text, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (!_finished)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text(
                  '✓ $_correct',
                  style: TextStyle(
                    color: p.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _finished ? _buildResult(p) : _buildQuestion(p),
    );
  }

  // ---- Question -----------------------------------------------------------

  Widget _buildQuestion(AppPalette p) {
    final q = _q;
    final surahName = quranSurahs[q.surah - 1].name;
    final showPromptText =
        widget.config.promptMode == QuizPromptMode.text || _answerShown;

    return Column(
      children: [
        LinearProgressIndicator(
          value: (_index) / _total,
          minHeight: 4,
          backgroundColor: p.border.withValues(alpha: .4),
          color: p.accent,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            children: [
              Text(
                'Recite the next ${widget.config.answerLength} ayahs from',
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                '$surahName  ·  Ayah ${q.startAyah}',
                style: TextStyle(
                  color: p.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              quizCard(
                p,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showPromptText)
                      Text(
                        q.promptText,
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: QuranArabicStyle.ayah(
                          script: widget.script,
                          fontSize: widget.fontSize,
                          color: p.surfaceText,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Listen to the prompt ayah, then recall what follows.',
                          style: TextStyle(color: p.surfaceMuted, fontSize: 14),
                        ),
                      ),
                    const SizedBox(height: 12),
                    _PlayButton(
                      label: showPromptText ? 'Play ayah' : 'Play prompt',
                      onTap: () => _playRange(q.startAyah, q.startAyah),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (_hintCount > 0 || _answerShown) _buildAnswer(p),
            ],
          ),
        ),
        _buildControls(p),
      ],
    );
  }

  Widget _buildAnswer(AppPalette p) {
    final q = _q;
    final shownCount = _answerShown ? q.answerAyahs.length : _hintCount;
    return quizCard(
      p,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'ANSWER',
                style: TextStyle(
                  color: p.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              if (q.answerAyahs.isNotEmpty)
                _PlayButton(
                  compact: true,
                  label: 'Play',
                  onTap: () =>
                      _playRange(q.answerAyahs.first, q.answerAyahs.last),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < shownCount; i++) ...[
            if (i > 0) Divider(height: 18, color: p.border),
            _AnswerRow(
              ayah: q.answerAyahs[i],
              text: q.answerTexts[i],
              script: widget.script,
              fontSize: widget.fontSize,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControls(AppPalette p) {
    final canHint =
        !_answerShown && _hintCount < _q.answerAyahs.length;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canHint ? _hint : null,
                  icon: const Icon(Icons.lightbulb_outline_rounded, size: 19),
                  label: Text(
                    _hintCount == 0 ? 'Hint' : 'Next ayah',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.accent,
                    side: BorderSide(color: p.accent.withValues(alpha: .5)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _answerShown
                      ? null
                      : () => setState(() => _answerShown = true),
                  icon: const Icon(Icons.visibility_rounded, size: 19),
                  label: const Text('Show answer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.text,
                    side: BorderSide(color: p.border),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _grade(false),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Missed'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.surface,
                    foregroundColor: p.text,
                    side: BorderSide(color: p.border),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _grade(true),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Got it'),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Result -------------------------------------------------------------

  Widget _buildResult(AppPalette p) {
    final pct = _total == 0 ? 0 : (_correct * 100 / _total).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_rounded, color: p.accent, size: 64),
            const SizedBox(height: 16),
            Text(
              '$_correct / $_total',
              style: TextStyle(
                color: p.text,
                fontSize: 44,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              '$pct% correct',
              style: TextStyle(
                color: p.muted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.config.scopeLabel,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  final int ayah;
  final String text;
  final String script;
  final String fontSize;

  const _AnswerRow({
    required this.ayah,
    required this.text,
    required this.script,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.accent.withValues(alpha: .18)),
            ),
            child: Text(
              '$ayah',
              style: TextStyle(
                color: p.accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: QuranArabicStyle.ayah(
            script: script,
            fontSize: fontSize,
            color: p.surfaceText,
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const _PlayButton({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AnimatedBuilder(
      animation: QuranAudioController.instance,
      builder: (context, _) {
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 16,
              vertical: compact ? 6 : 10,
            ),
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.accent.withValues(alpha: .25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, color: p.accent, size: 20),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: p.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12.5 : 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
