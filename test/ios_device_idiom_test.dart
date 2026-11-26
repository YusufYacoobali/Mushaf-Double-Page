import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushaf_two_page/utils/ios_device_idiom.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mushaf_two_page/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('UIKit iPad idiom enables the legacy iPad layout', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isIPad');
      return true;
    });
    expect(await IosDeviceIdiom.isIPad(), isTrue);
  });

  test('UIKit phone idiom leaves unfolded iPhone layouts adaptive', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await IosDeviceIdiom.isIPad(), isFalse);
  });

  test('missing native channel fails safely', () async {
    expect(await IosDeviceIdiom.isIPad(), isFalse);
  });

  test('non-iOS devices never query the UIKit channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (call) async {
      fail('The iOS device channel must not be called on Android');
    });
    expect(await IosDeviceIdiom.isIPad(), isFalse);
  });
}
