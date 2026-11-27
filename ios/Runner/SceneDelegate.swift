import Flutter
import UIKit

// Forward scene callbacks to Flutter/plugins. UIScene callbacks replace the
// old UIApplicationDelegate UI-activation callbacks on iOS 27.
class SceneDelegate: FlutterSceneDelegate {
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    UIApplication.shared.isIdleTimerDisabled = true
    ReaderDisplayRegions.shared.attach(to: window?.rootViewController?.view)
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    UIApplication.shared.isIdleTimerDisabled = false
    super.sceneWillResignActive(scene)
  }
}

// UIKit's division frames, in Flutter view points, are the source of layout
// geometry. Never infer a hinge from the window midpoint or its angle.
final class ReaderDisplayRegions: NSObject, FlutterStreamHandler {
  static let shared = ReaderDisplayRegions()
  private var sink: FlutterEventSink?
  private var probe: ReaderRegionProbe?
  private var latest: NSDictionary = [:]

  func attach(to view: UIView?) {
    guard UIDevice.current.userInterfaceIdiom != .pad, let view else { return }
    if probe?.superview !== view {
      probe?.removeFromSuperview()
      let next = ReaderRegionProbe(frame: view.bounds)
      next.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      next.isUserInteractionEnabled = false
      next.onChange = { [weak self] value in
        guard let self, !self.latest.isEqual(to: value) else { return }
        self.latest = value as NSDictionary
        self.sink?(value)
      }
      view.addSubview(next)
      probe = next
    }
    probe?.setNeedsLayout()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    events(latest)
    probe?.setNeedsLayout()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

final class ReaderRegionProbe: UIView {
  var onChange: (([String: Any]) -> Void)?
  private var hingeClosed = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    #if MUSHAF_DUO_SDK
    if #available(iOS 27.1, *) {
      addInteraction(UIHingeInteraction { [weak self] _, update in
        self?.hingeClosed = update.hinge?.status == .closed
        self?.setNeedsLayout()
      })
    }
    #endif
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    #if MUSHAF_DUO_SDK
    if #available(iOS 27.1, *) {
      let divisions = reservedRegions(kind: .division, options: .includeInactive)
      func frame(_ rect: CGRect) -> [String: CGFloat] {
        ["left": rect.minX, "top": rect.minY, "width": rect.width, "height": rect.height]
      }
      var event: [String: Any] = [
        "width": bounds.width, "height": bounds.height,
        "closed": hingeClosed,
        "divisions": divisions.map { region in
          ["left": region.frame.minX, "top": region.frame.minY,
           "width": region.frame.width, "height": region.frame.height,
           "active": region.isActive] as [String: Any]
        }
      ]
      if hingeClosed, let scene = window?.windowScene {
        let safe = safeAreaLayoutGuide.layoutFrame
        event["coverStrip"] = frame(CGRect(x: safe.maxX, y: safe.minY,
                                            width: bounds.maxX - safe.maxX, height: safe.height))
        var blocked = reservedRegions(kind: .occlusion, options: []).map { $0.frame }
        blocked += divisions.filter { $0.isActive }.map { $0.frame }
        if let status = scene.statusBarManager, !status.isStatusBarHidden {
          blocked.append(convert(status.statusBarFrame, from: scene.coordinateSpace))
        }
        event["coverObstructions"] = blocked.filter { !$0.isEmpty }.map(frame)
      }
      onChange?(event)
    }
    #endif
  }
}
