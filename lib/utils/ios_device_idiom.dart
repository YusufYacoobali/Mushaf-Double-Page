import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A device-family hint, not a layout breakpoint. In particular, a wide
/// unfolded iPhone is still a phone and can show two facing Quran pages.
class IosDeviceIdiom {
  static const MethodChannel _channel = MethodChannel('mushaf_two_page/device');

  static Future<bool> isIPad() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isIPad') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
