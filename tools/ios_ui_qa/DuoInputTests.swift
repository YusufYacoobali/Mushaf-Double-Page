import XCTest

// The host can read this test runner's own Documents directory on the
// disposable simulator. The reader has no input or test-command channel.
final class DuoInputTests: XCTestCase {
  @MainActor
  func testInput() throws {
    continueAfterFailure = false
    let reader = XCUIApplication(bundleIdentifier: ReaderAppIdentity.bundleID)
    reader.activate()
    XCTAssertTrue(reader.wait(for: .runningForeground, timeout: 20))
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let command = directory.appendingPathComponent("duo-command.json")
    let reply = directory.appendingPathComponent("duo-reply.json")
    try Data().write(to: directory.appendingPathComponent("duo-input-ready"), options: .atomic)
    var idleSince = Date()
    while Date().timeIntervalSince(idleSince) < 120 {
      guard let input = try? Data(contentsOf: command) else {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        continue
      }
      let data = try XCTUnwrap(JSONSerialization.jsonObject(with: input) as? [String: Any])
      try FileManager.default.removeItem(at: command)
      let action = try XCTUnwrap(data["action"] as? String)
      let id = try XCTUnwrap(data["id"] as? String)
      if action != "finish" {
        let frame = reader.frame
        let size = try XCTUnwrap(data["size"] as? [Double])
        XCTAssertEqual(frame.width, CGFloat(size[0]), accuracy: 1)
        XCTAssertEqual(frame.height, CGFloat(size[1]), accuracy: 1)
        func coordinate(_ key: String) throws -> XCUICoordinate {
          let p = try XCTUnwrap(data[key] as? [Double])
          XCTAssertTrue(frame.contains(CGPoint(x: p[0], y: p[1])))
          return reader.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: p[0] - frame.minX, dy: p[1] - frame.minY))
        }
        let start = try coordinate("point")
        switch action {
        case "tap": start.tap()
        case "swipe": try start.press(forDuration: 0.06, thenDragTo: coordinate("end"))
        default: XCTFail("Unexpected input command " + action)
        }
      }
      try Data(id.utf8).write(to: reply, options: .atomic)
      if action == "finish" { return }
      idleSince = Date()
    }
    XCTFail("Host stopped requesting native input")
  }
}
