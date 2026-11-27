
// Installed only in the disposable visual-verification build.
private final class CoverTouchObserver: UIGestureRecognizer {
  static func install(_ window: UIWindow?) {
    guard ProcessInfo.processInfo.environment["READER_TOUCH_QA"] == "1",
          let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is CoverTouchObserver }) else { return }
    let observer = CoverTouchObserver(target: nil, action: nil)
    observer.cancelsTouchesInView = false
    observer.delaysTouchesBegan = false
    observer.delaysTouchesEnded = false
    window.addGestureRecognizer(observer)
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    defer { state = .failed }  // Observation never wins the gesture.
    guard let touch = touches.first, let window = view as? UIWindow else { return }
    let point = touch.location(in: window)
    let hit = window.hitTest(point, with: event)
    let row: [String: Any] = ["time": Date().timeIntervalSince1970,
      "x": point.x, "y": point.y, "keyWindow": window.isKeyWindow,
      "window": NSStringFromCGRect(window.bounds),
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
