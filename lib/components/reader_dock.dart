import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_palette.dart';
import '../utils/app_motion.dart';

class ReaderDock extends StatelessWidget {
  const ReaderDock({
    super.key,
    required this.portrait,
    required this.expanded,
    required this.onToggle,
    required this.palette,
    required this.zoom,
    required this.actions,
    this.ayahActions,
    this.audioControls,
  });
  final bool portrait;
  final bool expanded;
  final VoidCallback onToggle;
  final AppPalette palette;
  final Widget zoom;
  final List<Widget> actions;
  final Widget? ayahActions;
  final Widget? audioControls;
  Widget? get _separateAyahActions =>
      audioControls == null ? ayahActions : null;

  Widget _action(Widget child, int index, double reveal) {
    final t = Interval(
      index * .045,
      .75 + index * .045,
      curve: AppMotion.curve,
    ).transform(reveal);
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: portrait ? Offset(0, 5 * (1 - t)) : Offset(5 * (1 - t), 0),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Positioned(
    left: portrait ? 10 : null,
    right: portrait ? 10 : 6,
    top: portrait ? null : 12,
    bottom: 12,
    child: SafeArea(
      top: !portrait,
      left: portrait,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: expanded ? 1 : 0),
        duration: AppMotion.duration(context, expanded),
        curve: AppMotion.curve,
        builder: (context, reveal, _) => TweenAnimationBuilder<double>(
          tween: Tween(end: _separateAyahActions == null ? 0 : 44),
          duration: AppMotion.duration(context, _separateAyahActions != null),
          curve: AppMotion.curve,
          builder: (context, extra, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: audioControls == null ? 0 : (portrait ? 50 : 58)),
            duration: AppMotion.duration(context, audioControls != null),
            curve: AppMotion.curve,
            builder: (context, audioExtra, _) =>
                _contents(context, reveal, extra, audioExtra),
          ),
        ),
      ),
    ),
  );

  Widget _contents(
    BuildContext context,
    double reveal,
    double extra,
    double audioExtra,
  ) {
    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [palette.surfaceRaised, palette.readerBar],
      ),
      borderRadius: BorderRadius.circular(portrait ? 28 : 23),
      boxShadow: [
        BoxShadow(
          color: palette.shadow,
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    );
    final ayahPanel = MotionSwitcher(
      alignment: portrait ? Alignment.bottomCenter : Alignment.centerRight,
      offset: portrait ? const Offset(0, .15) : const Offset(.15, 0),
      child: _separateAyahActions == null
          ? const SizedBox.shrink(key: ValueKey('no-ayah'))
          : Material(
              key: const ValueKey('ayah'),
              color: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(19),
                side: BorderSide(color: palette.border),
              ),
              child: _separateAyahActions,
            ),
    );
    final tab = NavigationPullTab(
      portrait: portrait,
      expanded: expanded,
      reveal: reveal,
      palette: palette,
      onToggle: onToggle,
    );
    Widget fading(Widget child) => IgnorePointer(
      ignoring: !expanded,
      child: ExcludeSemantics(
        excluding: !expanded,
        child: Opacity(opacity: reveal, child: child),
      ),
    );
    final navigation = portrait
        ? SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  zoom,
                  Container(
                    width: 1,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    color: palette.border,
                  ),
                  for (var i = 0; i < actions.length; i++)
                    Expanded(child: _action(actions[i], i, reveal)),
                ],
              ),
            ),
          )
        : SizedBox(
            width: 52,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++)
                    _action(actions[i], i, reveal),
                  Divider(
                    height: 12,
                    indent: 12,
                    endIndent: 12,
                    color: palette.border,
                  ),
                  zoom,
                ],
              ),
            ),
          );
    final audio = MotionSwitcher(
      child: audioControls == null
          ? const SizedBox.shrink(key: ValueKey('no-dock-audio'))
          : KeyedSubtree(
              key: const ValueKey('dock-audio'),
              child: audioControls!,
            ),
    );
    final panel = Container(
      key: const ValueKey('reader-navigation-panel'),
      height: portrait ? 56 + audioExtra : null,
      width: portrait ? null : 52 + audioExtra,
      decoration: decoration,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(portrait ? 28 : 23),
        border: Border.all(color: palette.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(portrait ? 28 : 23),
        child: portrait
            ? Column(
                children: [
                  ClipRect(
                    child: SizedBox(
                      height: audioExtra,
                      child: OverflowBox(
                        alignment: Alignment.bottomCenter,
                        minHeight: 50,
                        maxHeight: 50,
                        child: Column(
                          children: [
                            Expanded(child: audio),
                            Divider(
                              height: 1,
                              thickness: 1,
                              indent: 14,
                              endIndent: 14,
                              color: palette.border,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  navigation,
                ],
              )
            : Row(
                children: [
                  ClipRect(
                    child: SizedBox(
                      width: audioExtra,
                      child: OverflowBox(
                        alignment: Alignment.centerRight,
                        minWidth: 58,
                        maxWidth: 58,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Center(
                                child: SingleChildScrollView(child: audio),
                              ),
                            ),
                            VerticalDivider(
                              width: 6,
                              thickness: 1,
                              indent: 14,
                              endIndent: 14,
                              color: palette.border,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  navigation,
                ],
              ),
      ),
    );
    if (portrait) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SizedBox(
            width: double.infinity,
            height: 24 + (54 + extra + audioExtra) * reveal,
            child: Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [
                if (reveal > 0) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 22 + 10 * (1 - reveal),
                    child: fading(panel),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 84 + audioExtra,
                    child: fading(ayahPanel),
                  ),
                ],
                tab,
              ],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 22 + (50 + extra + audioExtra) * reveal,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          if (reveal > 0) ...[
            Positioned(
              left: 20 + 10 * (1 - reveal),
              top: 0,
              bottom: 0,
              child: fading(panel),
            ),
            Positioned(
              left: 78 + audioExtra,
              width: 38,
              top: 0,
              bottom: 0,
              child: fading(
                Center(child: SingleChildScrollView(child: ayahPanel)),
              ),
            ),
          ],
          tab,
        ],
      ),
    );
  }
}

/// The curved tab overlaps the dock's edge so it reads as one continuous piece.
class NavigationPullTab extends StatelessWidget {
  const NavigationPullTab({
    super.key,
    required this.portrait,
    required this.expanded,
    required this.palette,
    required this.onToggle,
    this.reveal,
  });
  final bool portrait;
  final bool expanded;
  final double? reveal;
  final AppPalette palette;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: expanded ? 'Collapse navigation' : 'Open navigation',
    child: Semantics(
      button: true,
      label: expanded ? 'Collapse navigation' : 'Open navigation',
      child: PressMotion(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: CustomPaint(
            size: portrait ? const Size(72, 24) : const Size(22, 72),
            painter: _PullTabPainter(
              portrait,
              reveal ?? (expanded ? 1 : 0),
              palette,
            ),
          ),
        ),
      ),
    ),
  );
}

class _PullTabPainter extends CustomPainter {
  const _PullTabPainter(this.portrait, this.reveal, this.palette);
  final bool portrait;
  final double reveal;
  final AppPalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    final w = portrait ? size.height : size.width;
    final h = portrait ? size.width : size.height;
    if (portrait) {
      canvas.translate(size.width, 0);
      canvas.rotate(math.pi / 2);
    }
    final contour = Path()
      ..moveTo(w, 0)
      ..cubicTo(w * .45, 0, 0, 10, 0, 22)
      ..lineTo(0, h - 22)
      ..cubicTo(0, h - 10, w * .45, h, w, h);
    final fill = Path.from(contour)..close();
    canvas.drawPath(fill, Paint()..color = palette.surfaceRaised);
    canvas.drawPath(
      contour,
      Paint()
        ..color = palette.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final x = w * .52;
    final y = h / 2;
    final direction = 2 * reveal - 1;
    final arrow = Path()
      ..moveTo(x - direction * 2, y - 4)
      ..lineTo(x + direction * 2, y)
      ..lineTo(x - direction * 2, y + 4);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = palette.readerIcon
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PullTabPainter oldDelegate) =>
      oldDelegate.portrait != portrait ||
      oldDelegate.reveal != reveal ||
      oldDelegate.palette != palette;
}

class ReaderZoom extends StatelessWidget {
  const ReaderZoom({
    super.key,
    required this.portrait,
    required this.palette,
    required this.scale,
    required this.minimum,
    required this.onDecrease,
    required this.onIncrease,
  });
  final bool portrait;
  final AppPalette palette;
  final double scale;
  final double minimum;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  Widget _button({required bool increase}) {
    final enabled = increase ? scale < 1.0 : scale > minimum;
    return PressMotion(
      enabled: enabled,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.surfaceRaised,
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(alpha: .08),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IconButton(
          tooltip: increase ? 'Zoom in' : 'Zoom out',
          padding: EdgeInsets.zero,
          onPressed: enabled ? (increase ? onIncrease : onDecrease) : null,
          icon: Icon(
            increase ? Icons.add : Icons.remove,
            size: 19,
            color: enabled
                ? (palette.isDark
                      ? const Color(0xFFE2C78D)
                      : const Color(0xFF8C744B))
                : palette.muted.withValues(alpha: .4),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: portrait ? 5 : 0,
        vertical: portrait ? 0 : 7,
      ),
      child: Text(
        '${(scale * 100).round()}%',
        style: TextStyle(
          color: palette.readerIcon,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return portrait
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _button(increase: false),
              label,
              _button(increase: true),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _button(increase: true),
              label,
              _button(increase: false),
            ],
          );
  }
}
