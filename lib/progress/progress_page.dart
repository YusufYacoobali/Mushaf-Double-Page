import 'quran_reminder.dart';
import 'package:flutter/material.dart';
import 'package:mushaf_two_page/utils/app_palette.dart';
import 'package:mushaf_two_page/utils/app_motion.dart';
import 'reading_progress_store.dart';
import 'journey_store.dart';
import 'app_time_tracker.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  JourneyStats? _stats;
  int _streak = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AppTimeTracker.instance.flush();
    final stats = await JourneyStore.load();
    final progress = await ReadingProgressStore.load();
    if (mounted) {
      setState(() {
        _stats = stats;
        _streak = progress.streak;
      });
    }
  }

  String _time(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
  }

  String _since(DateTime? since) {
    if (since == null) return 'Your story starts with your next page.';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Since ${since.day} ${months[since.month - 1]} ${since.year} · On this device';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final stats = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('Your Quran Journey')),
      body: SafeArea(
        top: false,
        child: stats == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF423B32), Color(0xFF211E1B)],
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFF9B8056,
                              ).withValues(alpha: .5),
                            ),
                          ),
                          child: Stack(
                            children: [
                              const Positioned(
                                right: -24,
                                top: -16,
                                width: 170,
                                height: 190,
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _JourneyArtwork(),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'EVERY RETURN ADDS UP',
                                      style: TextStyle(
                                        color: Color(0xFFE2C78D),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.8,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      quranRecitationHadith,
                                      style: TextStyle(
                                        color: Color(0xFFFCF8EF),
                                        fontSize: 20,
                                        height: 1.45,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      quranRecitationHadithAttribution,
                                      style: TextStyle(
                                        color: Color(0xFFE2C78D),
                                        fontSize: 12,
                                        height: 1.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _streakFigure(
                                            context,
                                            _streak,
                                            'Current streak',
                                          ),
                                        ),
                                        Container(
                                          width: 1,
                                          height: 46,
                                          color: const Color(0xFF77634B),
                                        ),
                                        const SizedBox(width: 24),
                                        Expanded(
                                          child: _streakFigure(
                                            context,
                                            stats.bestStreak,
                                            'Best streak',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'App lifetime statistics',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _since(stats.since),
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 700
                                ? 4
                                : constraints.maxWidth < 280
                                ? 1
                                : 2;
                            final width =
                                (constraints.maxWidth - 12 * (columns - 1)) /
                                columns;
                            final cards = [
                              _stat(
                                context,
                                width,
                                Icons.auto_stories_outlined,
                                'Pages opened',
                                stats.pagesOpened,
                                'Each page you return to',
                              ),
                              _stat(
                                context,
                                width,
                                Icons.headphones_outlined,
                                'Ayahs listened to',
                                stats.ayahsListened,
                                'Every recitation counts',
                              ),
                              _stat(
                                context,
                                width,
                                Icons.translate_rounded,
                                'Translations read',
                                stats.translationsRead,
                                'Moments of understanding',
                              ),
                              _stat(
                                context,
                                width,
                                Icons.schedule_rounded,
                                'Reading time',
                                stats.readingSeconds,
                                'With the Mushaf open',
                                time: true,
                              ),
                              _stat(
                                context,
                                width,
                                Icons.graphic_eq_rounded,
                                'Listening time',
                                stats.listeningSeconds,
                                'In the company of Quran',
                                time: true,
                              ),
                              _stat(
                                context,
                                width,
                                Icons.calendar_today_outlined,
                                'Active days',
                                stats.activeDays,
                                'Days you made room',
                              ),
                              _stat(
                                context,
                                width,
                                Icons.menu_book_outlined,
                                'Surahs explored',
                                stats.surahsListened,
                                'Through your listening',
                              ),
                              _stat(
                                context,
                                width,
                                Icons.hourglass_bottom_rounded,
                                'Total app time',
                                stats.appSeconds,
                                'Across your whole journey',
                                time: true,
                              ),
                            ];
                            return Column(
                              children: [
                                for (
                                  var start = 0;
                                  start < cards.length;
                                  start += columns
                                )
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (
                                            var i = start;
                                            i < start + columns &&
                                                i < cards.length;
                                            i++
                                          ) ...[
                                            if (i > start)
                                              const SizedBox(width: 12),
                                            Expanded(child: cards[i]),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: () => Navigator.popUntil(
                            context,
                            (route) => route.isFirst,
                          ),
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('Return to the Quran'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _streakFigure(BuildContext context, int days, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$days ${days == 1 ? 'day' : 'days'}',
        style: const TextStyle(
          color: Color(0xFFF4DEB0),
          fontSize: 25,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: const TextStyle(color: Color(0xFFCDC2B2), fontSize: 12),
      ),
    ],
  );
  Widget _stat(
    BuildContext context,
    double width,
    IconData icon,
    String title,
    int value,
    String caption, {
    bool time = false,
  }) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: palette.accent, size: 23),
            const SizedBox(height: 18),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: AppMotion.reduced(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 700),
              curve: AppMotion.curve,
              builder: (context, number, _) => FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  time ? _time(number.round()) : _number(number.round()),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 29,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              style: TextStyle(
                color: palette.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              caption,
              style: TextStyle(color: palette.muted, fontSize: 10, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  String _number(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
}

/// Quiet linework drawn at native resolution, echoing an open Mushaf.
class _JourneyArtwork extends CustomPainter {
  const _JourneyArtwork();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFE2C78D).withValues(alpha: .1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset(size.width * .7, size.height * .35),
        35 + i * 20,
        p,
      );
    }
    final path = Path()
      ..moveTo(80, 85)
      ..quadraticBezierTo(45, 62, 20, 75)
      ..lineTo(20, 140)
      ..quadraticBezierTo(48, 126, 80, 150)
      ..quadraticBezierTo(108, 126, 140, 140)
      ..lineTo(140, 75)
      ..quadraticBezierTo(108, 62, 80, 85)
      ..lineTo(80, 150);
    canvas.drawPath(path, p..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_JourneyArtwork oldDelegate) => false;
}
