import 'package:flutter/material.dart';
import '../utils/reader_layout.dart';

/// Secondary screens stay in one unobstructed region and keep readable line
/// lengths. Their existing scrolling, state and actions are unchanged on resize.
class AdaptiveSurface extends StatelessWidget {
  const AdaptiveSurface({super.key, required this.child, this.maxWidth = 900});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final regions = safeDisplayRegions(
        constraints.biggest,
        media.padding,
        media.displayFeatures,
      );
      final region = regions.reduce(
        (a, b) => a.width * a.height >= b.width * b.height ? a : b,
      );
      final width = region.width.clamp(0.0, maxWidth);
      final bounds = Rect.fromLTWH(
        region.center.dx - width / 2,
        region.top,
        width,
        region.height,
      );
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: bounds,
              child: MediaQuery(
                data: media.copyWith(
                  size: bounds.size,
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                  displayFeatures: const [],
                ),
                child: child,
              ),
            ),
          ],
        ),
      );
    },
  );
}
