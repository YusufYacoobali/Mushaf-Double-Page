import Flutter
import UIKit

// Forward scene callbacks to Flutter/plugins. UIScene callbacks replace the
// old UIApplicationDelegate UI-activation callbacks on iOS 27.
class SceneDelegate: FlutterSceneDelegate {
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    UIApplication.shared.isIdleTimerDisabled = true
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    UIApplication.shared.isIdleTimerDisabled = false
    super.sceneWillResignActive(scene)
  }
}
