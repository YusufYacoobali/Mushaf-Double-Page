import 'package:flutter/material.dart';

/// Shared, restrained motion: a soft arrival and a quicker departure.
abstract final class AppMotion {
  static const enter = Duration(milliseconds: 380);
  static const exit = Duration(milliseconds: 260);
  static const curve = Curves.easeOutCubic;
  static const reverseCurve = Curves.easeInCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static Duration duration(BuildContext context, [bool opening = true]) =>
      reduced(context) ? Duration.zero : (opening ? enter : exit);

  static AnimationStyle style(BuildContext context) => AnimationStyle(
    duration: duration(context),
    reverseDuration: duration(context, false),
    curve: curve,
    reverseCurve: reverseCurve,
  );
}

/// Keep Material route results and back navigation while refining Android and
/// desktop arrivals. iOS retains its interactive Cupertino transition.
class PremiumPageTransitionsBuilder extends PageTransitionsBuilder {
  const PremiumPageTransitionsBuilder();
  @override
  Duration get transitionDuration => AppMotion.enter;
  @override
  Duration get reverseTransitionDuration => AppMotion.exit;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.reduced(context)) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = AppMotion.curve.transform(animation.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: Transform.scale(scale: .985 + .015 * t, child: child),
          ),
        );
      },
    );
  }
}

/// Adds tactile press motion without taking ownership of the child's gestures.
/// Scrolling, cancellation, keyboard activation and semantics stay with it.
class PressMotion extends StatefulWidget {
  const PressMotion({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<PressMotion> createState() => _PressMotionState();
}

class _PressMotionState extends State<PressMotion> {
  bool _pressed = false;
  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
    onPointerUp: (_) => _setPressed(false),
    onPointerCancel: (_) => _setPressed(false),
    child: AnimatedScale(
      scale: _pressed && widget.enabled ? .93 : 1,
      duration: AppMotion.reduced(context)
          ? Duration.zero
          : Duration(milliseconds: _pressed ? 90 : 220),
      curve: AppMotion.curve,
      child: widget.child,
    ),
  );
}

/// Retains outgoing content until its exit finishes, but makes it untappable.
/// The retained child is excluded from hit testing and accessibility.
class MotionSwitcher extends StatelessWidget {
  const MotionSwitcher({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.offset = const Offset(0, .08),
  });
  final Widget child;
  final Alignment alignment;
  final Offset offset;
  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: AppMotion.duration(context),
    reverseDuration: AppMotion.duration(context, false),
    curve: AppMotion.curve,
    alignment: alignment,
    clipBehavior: Clip.none,
    child: AnimatedSwitcher(
      duration: AppMotion.duration(context),
      reverseDuration: AppMotion.duration(context, false),
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        clipBehavior: Clip.none,
        children: [
          for (final child in previous)
            IgnorePointer(child: ExcludeSemantics(child: child)),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: offset, end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: child,
    ),
  );
}
