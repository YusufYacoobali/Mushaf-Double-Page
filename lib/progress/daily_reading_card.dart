import 'package:flutter/material.dart';

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

  String get title => streak <= 1
      ? 'A little time. A lasting connection.'
      : streak % 7 == 0
      ? 'A week of showing up. Beautifully done.'
      : 'You made time for what matters.';
  String get message => streak <= 1
      ? 'Welcome. Even a few thoughtful verses can make this a meaningful part of your day.'
      : 'Welcome back. Your $streak days of returning to the Quran reflect care and commitment. Keep going at your own pace.';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(compact ? 18 : 28),
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
                        : 'A MOMENT FOR YOURSELF',
                    style: const TextStyle(
                      color: Color(0xFFE2C78D),
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Dismiss welcome',
                    onPressed: onClose,
                    icon: const Icon(
                      Icons.close,
                      color: Color(0xFFE5DDD1),
                      size: 18,
                    ),
                  ),
              ],
            ),
            SizedBox(height: compact ? 10 : 26),
            Text(
              title,
              style: TextStyle(
                color: const Color(0xFFFFFCF2),
                fontSize: compact ? 19 : 29,
                height: 1.25,
                fontWeight: FontWeight.w500,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: const Color(0xFFDDD2C1),
                fontSize: compact ? 12 : 15,
                height: 1.6,
              ),
            ),
            if (!compact) ...[
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
                          color: i < (streak == 0 ? 0 : (streak - 1) % 7 + 1)
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
          ],
        ),
      ),
    );
  }
}
