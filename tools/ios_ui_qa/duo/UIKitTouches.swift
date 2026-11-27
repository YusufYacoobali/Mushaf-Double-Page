
import UserNotifications

// Installed only in the disposable visual-verification build.
private final class CoverTouchObserver: UIGestureRecognizer {
  private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

  static func install(_ window: UIWindow?) {
    guard UIDevice.current.userInterfaceIdiom == .phone, let window else { return }
    // Query the real OS decision. A clear screenshot can precede presentation
    // of the deferred first-launch prompt, even after the Quran is rendered.
    guard !(window.gestureRecognizers ?? []).contains(where: { $0 is CoverTouchObserver }) else { return }
    recordAuthorization()
    let observer = CoverTouchObserver(target: nil, action: nil)
    observer.cancelsTouchesInView = false
    observer.delaysTouchesBegan = false
    observer.delaysTouchesEnded = false
    window.addGestureRecognizer(observer)
    Timer.scheduledTimer(timeInterval: 0.15, target: observer,
                         selector: #selector(reportRequestedHit(_:)), userInfo: nil, repeats: true)
  }

  private static func recordAuthorization() {
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("duo-notification.json")
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      try? Data(String(settings.authorizationStatus.rawValue).utf8).write(to: output, options: .atomic)
    }
  }

  // Query UIKit independently of incoming events. This distinguishes an area
  // outside Flutter's native view from input lost before the reader window.
  @objc private func reportRequestedHit(_ timer: Timer) {
    guard let window = view as? UIWindow else { timer.invalidate(); return }
    let refresh = documents.appendingPathComponent("duo-refresh-permission")
    if FileManager.default.fileExists(atPath: refresh.path) {
      try? FileManager.default.removeItem(at: refresh)
      Self.recordAuthorization()
    }
    let input = documents.appendingPathComponent("duo-hit-request.json")
    guard let bytes = try? Data(contentsOf: input),
          let request = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
          let id = request["id"] as? String, let xy = request["point"] as? [Double], xy.count == 2 else { return }
    try? FileManager.default.removeItem(at: input)
    let hit = window.hitTest(CGPoint(x: xy[0], y: xy[1]), with: nil)
    let row: [String: Any] = ["id": id, "keyWindow": window.isKeyWindow,
      "foreground": window.windowScene?.activationState == .foregroundActive,
      "hit": hit.map { String(describing: type(of: $0)) } ?? "none",
      "size": [window.bounds.width, window.bounds.height]]
    if let data = try? JSONSerialization.data(withJSONObject: row) {
      try? data.write(to: documents.appendingPathComponent("duo-hit.json"), options: .atomic)
    }
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    defer { state = .failed }  // Observation never wins the gesture.
    guard let touch = touches.first, let window = view as? UIWindow else { return }
    let point = touch.location(in: window)
    let hit = window.hitTest(point, with: event)
    let row: [String: Any] = ["time": Date().timeIntervalSince1970,
      "x": point.x, "y": point.y, "keyWindow": window.isKeyWindow,
      "window": [window.bounds.width, window.bounds.height],
      "hit": hit.map { String(describing: type(of: $0)) } ?? "none",
      "target": touch.view.map { String(describing: type(of: $0)) } ?? "none"]
    let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("duo-uikit.jsonl")
    if !FileManager.default.fileExists(atPath: file.path) {
      FileManager.default.createFile(atPath: file.path, contents: nil)
    }
    if let data = try? JSONSerialization.data(withJSONObject: row),
       let handle = try? FileHandle(forWritingTo: file) {
      handle.seekToEndOfFile()
      handle.write(data + Data([10]))
      handle.closeFile()
    }
  }
}
