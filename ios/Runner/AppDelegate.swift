import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // An iPad mini and an unfolded phone may have similarly wide windows.
    // Use UIKit's hardware idiom instead of guessing from Flutter dimensions.
    if let controller = window?.rootViewController as? FlutterViewController {
      let deviceChannel = FlutterMethodChannel(
        name: "mushaf_two_page/device",
        binaryMessenger: controller.binaryMessenger
      )
      deviceChannel.setMethodCallHandler { call, result in
        if call.method == "isIPad" {
          result(UIDevice.current.userInterfaceIdiom == .pad)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    application.isIdleTimerDisabled = true
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    application.isIdleTimerDisabled = true
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    application.isIdleTimerDisabled = false
    super.applicationWillResignActive(application)
  }
}
