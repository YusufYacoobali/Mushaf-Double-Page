import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // iOS 27 requires UIScene. With the scene lifecycle, the implicit Flutter
  // engine (and the scene's FlutterViewController) does not yet exist at
  // didFinishLaunchingWithOptions. Register plugins and channels on the engine.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // iPad mini and an unfolded iPhone can have similar window widths.
    // This hardware-family query must be available before the reader builds.
    let deviceChannel = FlutterMethodChannel(
      name: "mushaf_two_page/device",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    FlutterEventChannel(
      name: "mushaf_two_page/display_regions",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setStreamHandler(ReaderDisplayRegions.shared)
    deviceChannel.setMethodCallHandler { call, result in
      if call.method == "isIPad" {
        result(UIDevice.current.userInterfaceIdiom == .pad)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
