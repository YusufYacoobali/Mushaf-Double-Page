import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'reading_progress_store.dart';
import 'daily_reading_card.dart';

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
    return Scaffold(
      backgroundColor: palette.scaffold,
      appBar: AppBar(title: const Text('Your daily practice')),
      body: _progress == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DailyReadingCard(streak: _progress!.streak),
                      const SizedBox(height: 26),
                      Text(
                        'A practice that grows with you',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Some days, a page. Some days, a verse. Make space to read, reflect and return.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.muted, height: 1.6),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Continue your reading'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
