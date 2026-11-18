import 'dart:ui';

/// Native division coordinates belong to one window size. Ignore stale frames
/// during rotation until UIKit reports geometry for the new Flutter viewport.
class IosDisplayRegions {
  IosDisplayRegions.fromEvent(dynamic event) {
    if (event is! Map) return;
    size = Size(_number(event['width']), _number(event['height']));
    closed = event['closed'] == true;
    final divisions = event['divisions'];
    if (divisions is! List) return;
    if (!size.width.isFinite || !size.height.isFinite || size.isEmpty) return;
    features = [
      for (final region in divisions)
        if (region is Map && _validRegion(region))
          DisplayFeature(
            bounds: Rect.fromLTWH(
              _number(region['left']),
              _number(region['top']),
              _number(region['width']),
              _number(region['height']),
            ),
            type: DisplayFeatureType.fold,
            state: region['active'] == true
                ? DisplayFeatureState.postureHalfOpened
                : DisplayFeatureState.postureFlat,
          ),
    ];
  }
  Size size = Size.zero;
  bool closed = false;
  List<DisplayFeature> features = const [];
  static bool _validRegion(Map region) {
    final values = ['left', 'top', 'width', 'height'].map((key) => region[key]);
    return values.every((v) => v is num && v.isFinite) &&
        (region['width'] as num) >= 0 &&
        (region['height'] as num) >= 0 &&
        ((region['width'] as num) > 0 || (region['height'] as num) > 0);
  }

  static double _number(dynamic value) => value is num ? value.toDouble() : 0;
  List<DisplayFeature> forSize(Size viewport) =>
      (size.width - viewport.width).abs() < 1 &&
          (size.height - viewport.height).abs() < 1
      ? features
      : const [];
}
