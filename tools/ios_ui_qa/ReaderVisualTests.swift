import XCTest

final class ReaderVisualTests: XCTestCase {
  @MainActor
  func testPreparePortrait() throws {
    continueAfterFailure = false
    let reader = XCUIApplication(bundleIdentifier: ReaderAppIdentity.bundleID)
    // Prepare the already-installed reader without changing its page or zoom.
    reader.activate()
    XCTAssertTrue(reader.wait(for: .runningForeground, timeout: 20),
                  "portrait: reader not foreground")
    dismissNotification(timeout: 10)
    XCUIDevice.shared.orientation = .portrait
    waitForOrientation(reader, landscape: false)
    dismissNotification(timeout: 10)
    // Geometry can pass underneath a system sheet. Check the visible app before
    // the workflow takes its separate, genuine portrait screenshot.
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for _ in 0..<5 {
      XCTAssertFalse(springboard.alerts.firstMatch.exists,
                     "portrait: a system alert still covers the reader")
      XCTAssertFalse(reader.alerts.firstMatch.exists,
                     "portrait: a reader alert still covers the page")
      Thread.sleep(forTimeInterval: 0.5)
    }
  }

  @MainActor
  func testRotateLandscape() throws {
    continueAfterFailure = false
    let reader = XCUIApplication(bundleIdentifier: ReaderAppIdentity.bundleID)
    // Activate the already-installed reader without resetting its page or zoom.
    reader.activate()
    XCTAssertTrue(reader.wait(for: .runningForeground, timeout: 20),
                  "rotation: reader not foreground")
    dismissNotification()
    XCUIDevice.shared.orientation = .portrait
    waitForOrientation(reader, landscape: false)
    XCUIDevice.shared.orientation = .landscapeLeft
    waitForOrientation(reader, landscape: true)
    dismissNotification(timeout: 10)
    // A system permission sheet can cover the reader while its geometry still
    // passes. Require a clear screen before the workflow takes its real PNG.
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for _ in 0..<5 {
      XCTAssertFalse(springboard.alerts.firstMatch.exists,
                     "rotation: a system alert still covers the reader")
      XCTAssertFalse(reader.alerts.firstMatch.exists,
                     "rotation: a reader alert still covers the page")
      Thread.sleep(forTimeInterval: 0.5)
    }
    // Retain a diagnostic only. The workflow still pairs a separate, genuine
    // screenshot with fresh reader geometry after this rotation-only test.
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "reader-landscape-rotation"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  func testLayout() throws {
    continueAfterFailure = false
    let reader = XCUIApplication(bundleIdentifier: ReaderAppIdentity.bundleID)
    reader.activate()
    dismissNotification()
    XCTAssertTrue(reader.wait(for: .runningForeground, timeout: 20))
    XCUIDevice.shared.orientation = .portrait
    waitForOrientation(reader, landscape: false)
    // Match the original v5 capture's settled, collapsed portrait state.
    Thread.sleep(forTimeInterval: 18)
    dismissNotification()
    try capture("portrait.png")

    XCUIDevice.shared.orientation = .landscapeLeft
    waitForOrientation(reader, landscape: true)
    dismissNotification()
    let zoom = reader.staticTexts["70%"]
    if !zoom.exists || !zoom.isHittable {
      let tab = reader.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open navigation")).firstMatch
      if tab.waitForExistence(timeout: 2) {
        touch(tab, in: reader)
      } else {
        let frame = reader.frame
        reader.coordinate(withNormalizedOffset: CGVector(dx: (frame.width - 15) / frame.width, dy: 0.5)).tap()
      }
    }
    Thread.sleep(forTimeInterval: 0.5)
    try capture("landscape.png")
  }

  @MainActor
  func testNavigation() throws {
    let reader = XCUIApplication(bundleIdentifier: ReaderAppIdentity.bundleID)
    reader.activate()
    dismissNotification()
    XCTAssertTrue(reader.wait(for: .runningForeground, timeout: 20), "launch: reader not foreground")
    XCUIDevice.shared.orientation = .landscapeLeft
    waitForOrientation(reader, landscape: true)
    let collapse = reader.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Collapse navigation")).firstMatch
    if collapse.exists { touch(collapse, in: reader) }
    try capture("navigation-closed.png")
    let open = reader.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open navigation")).firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 3), "navigation: missing collapsed tab")
    touch(open, in: reader)
    if !collapse.waitForExistence(timeout: 3) {
      // The large 13-inch iPad sometimes reports a valid Flutter AX button
      // frame yet its first touch does not reach the narrow edge pull-tab.
      // Try the tab's visible screen-edge location as a genuine XCTest tap.
      reader.coordinate(withNormalizedOffset: CGVector(dx: 0.992, dy: 0.5)).tap()
      Thread.sleep(forTimeInterval: 0.7)
    }
    if !collapse.waitForExistence(timeout: 3) {
      // Last bounded attempt: use the normal accessibility activation point
      // rather than a stale frame taken before the first animation.
      let retry = reader.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open navigation")).firstMatch
      if retry.waitForExistence(timeout: 2) { retry.tap() }
    }
    XCTAssertTrue(collapse.waitForExistence(timeout: 4),
                  "navigation: 13-inch screen stayed collapsed after actual tab and edge taps")
    try capture("navigation-open.png")
  }

  @MainActor
  func testZoom() throws {
    let reader = XCUIApplication(bundleIdentifier: ReaderAppIdentity.bundleID)
    reader.activate()
    dismissNotification()
    XCTAssertTrue(reader.wait(for: .runningForeground, timeout: 20), "launch: reader not foreground")
    XCUIDevice.shared.orientation = .portrait
    waitForOrientation(reader, landscape: false)
    try captureZooms(reader, orientation: "portrait", minimum: 70)
    XCUIDevice.shared.orientation = .landscapeLeft
    waitForOrientation(reader, landscape: true)
    try captureZooms(reader, orientation: "landscape", minimum: 60)
  }

  @MainActor
  private func touch(_ element: XCUIElement, in reader: XCUIApplication) {
    // Resolve the observed rectangle once. An element-relative coordinate
    // re-queries its changing label during the touch (Open -> Collapse).
    let box = element.frame
    let window = reader.frame
    reader.coordinate(withNormalizedOffset: CGVector(
      dx: (box.midX - window.minX) / window.width,
      dy: (box.midY - window.minY) / window.height
    )).tap()
    // Flutter's reveal animation is not represented by UIKit's idle state.
    Thread.sleep(forTimeInterval: 0.5)
  }

  @MainActor
  private func captureZooms(_ reader: XCUIApplication, orientation: String, minimum: Int) throws {
    // Validate and retain a real screenshot at EVERY 5% zoom step, not only
    // the endpoints. This catches a skipped/mislabelled intermediate value.
    for target in stride(from: minimum, through: 100, by: 5) {
      for step in 0..<24 {
        // Zoom taps do not restart the reader's ten-second hide timer. Renew
        // it before each target and every three taps, before reading AX labels.
        if step % 3 == 0 {
          let collapse = reader.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Collapse navigation")).firstMatch
          if collapse.exists {
            touch(collapse, in: reader)
          }
          let open = reader.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open navigation")).firstMatch
          if open.waitForExistence(timeout: 1) {
            touch(open, in: reader)
          }
        }
        let label = reader.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^(60|65|70|75|80|85|90|95|100)%$")).firstMatch
        if !label.exists || !label.isHittable {
          let tab = reader.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open navigation")).firstMatch
          if tab.exists { touch(tab, in: reader) }
          continue
        }
        let current = Int(label.label.replacingOccurrences(of: "%", with: ""))!
        if current == target { break }
        let action = current < target ? "Zoom in" : "Zoom out"
        let button = reader.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", action)).firstMatch
        // Flutter exposes the correct frame but XCTest's activation point can
        // be invalid after rotation/zoom. Touch the observed frame directly.
        if button.exists {
          touch(button, in: reader)
        }
        Thread.sleep(forTimeInterval: 0.2)
      }
      XCTAssertTrue(reader.staticTexts["\(target)%"].waitForExistence(timeout: 3))
      try capture("\(orientation)-\(target).png")
    }
  }

  @MainActor
  private func dismissNotification(timeout: TimeInterval = 3) {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    // Dismiss only this app's notification prompt on the disposable simulator.
    // Other permission prompts and unrelated alerts must remain test failures.
    // .containing(predicate) checks a DESCENDANT's label, but iOS 27
    // splits the permission title into several accessibility elements.
    // It therefore missed this genuine notification alert after rotation.
    // Look at the alert itself plus its static texts, and reject any other
    // permission/system alert rather than blindly dismissing it.
    let notification = springboard.alerts.firstMatch
    guard notification.waitForExistence(timeout: timeout) else { return }
    let alertText = ([notification.label] +
      notification.staticTexts.allElementsBoundByIndex.map { $0.label }
    ).joined(separator: " ")
    guard alertText.localizedCaseInsensitiveContains("Quran Dual Page") &&
          alertText.localizedCaseInsensitiveContains("Notifications") else {
      XCTFail("notification: unexpected system alert: " + alertText)
      return
    }
    let deny = notification.buttons.matching(NSPredicate(
      format: "label == %@ OR label == %@", "Don't Allow", "Don’t Allow"
    )).firstMatch
    guard deny.waitForExistence(timeout: 3) else {
      XCTFail("notification: the app's permission alert has no Don't Allow button")
      return
    }
    deny.tap()
    let dismissed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: notification
    )
    XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed,
                   "notification: the app's permission alert did not disappear")
  }

  @MainActor
  private func waitForOrientation(_ reader: XCUIApplication, landscape: Bool) {
    for _ in 0..<40 {
      let frame = reader.frame
      if frame.width > 0 && (frame.width > frame.height) == landscape { return }
      Thread.sleep(forTimeInterval: 0.5)
    }
    XCTFail("Reader did not enter the requested orientation; actual frame: \(reader.frame)")
  }

  @MainActor
  private func capture(_ filename: String) throws {
    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("reader-qa")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let reader = XCUIApplication(bundleIdentifier: ReaderAppIdentity.bundleID)
    let frame = reader.frame
    let dimensions: [String: Double] = ["width": Double(frame.width), "height": Double(frame.height)]
    let metadata = try JSONSerialization.data(withJSONObject: dimensions, options: [.sortedKeys])
    try metadata.write(to: directory.appendingPathComponent(filename + ".json"), options: .atomic)
    let shot = XCUIScreen.main.screenshot()
    try shot.pngRepresentation.write(to: directory.appendingPathComponent(filename), options: .atomic)
    let attachment = XCTAttachment(screenshot: shot)
    attachment.name = filename
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
