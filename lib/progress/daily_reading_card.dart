import 'package:flutter/material.dart';
import 'quran_reminder.dart';

class DailyReadingCard extends StatelessWidget {
  const DailyReadingCard({
    super.key,
    required this.streak,
    this.compact = false,
    this.onClose,
  });
  final int streak;
  final bool compact;
  final VoidCallback? onClose;

  Widget get _quote => Text(
    quranRecitationHadith,
    style: TextStyle(
      color: const Color(0xFFFFFCF2),
      fontSize: compact ? 19 : 29,
      height: 1.25,
      fontWeight: FontWeight.w500,
      letterSpacing: -.5,
    ),
  );
  Widget get _attribution => Text(
    quranRecitationHadithAttribution,
    style: TextStyle(
      color: const Color(0xFFDDD2C1),
      fontSize: compact ? 12 : 15,
      height: 1.6,
    ),
  );
  Widget get _dismiss => IconButton(
    tooltip: 'Dismiss welcome',
    style: IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
    onPressed: onClose,
    icon: const Icon(Icons.close, color: Color(0xFFE5DDD1), size: 18),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      padding: EdgeInsets.all(compact ? 16 : 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A4033), Color(0xFF25211D)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFB69B68).withValues(alpha: .65),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332B241D),
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: compact
          ? Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          right: onClose == null ? 0 : 52,
                        ),
                        child: _quote,
                      ),
                      const SizedBox(height: 12),
                      _attribution,
                    ],
                  ),
                ),
                if (onClose != null)
                  Positioned(top: 0, right: 0, child: _dismiss),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_outlined,
                        color: Color(0xFFE2C78D),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          streak > 1
                              ? '$streak DAYS OF CONNECTION'
                              : 'READING STREAK',
                          style: const TextStyle(
                            color: Color(0xFFE2C78D),
                            fontSize: 10,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (onClose != null) _dismiss,
                    ],
                  ),
                  const SizedBox(height: 26),
                  _quote,
                  const SizedBox(height: 12),
                  _attribution,
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            height: 5,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color:
                                  i < (streak == 0 ? 0 : (streak - 1) % 7 + 1)
                                  ? const Color(0xFFE2C78D)
                                  : const Color(0xFF655848),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'One day at a time. Every return counts.',
                    style: TextStyle(color: Color(0xFFDDD2C1), fontSize: 12),
                  ),
                ],
              ),
            ),
    ),
  );
}
