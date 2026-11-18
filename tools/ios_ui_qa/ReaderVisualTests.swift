import XCTest

final class ReaderVisualTests: XCTestCase {
  @MainActor
  func testReaderOrientations() throws {
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
    try captureZooms(reader, orientation: "portrait", minimum: 70)

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
    XCTAssertTrue(zoom.waitForExistence(timeout: 3), "Landscape reader must expose its original 70% zoom")
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
    for target in [minimum, 100] {
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
  private func dismissNotification() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let deny = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@ AND label ENDSWITH[c] %@", "Don", "Allow")).firstMatch
    if deny.waitForExistence(timeout: 3) { deny.tap() }
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
    let shot = XCUIScreen.main.screenshot()
    try shot.pngRepresentation.write(to: directory.appendingPathComponent(filename), options: .atomic)
    let attachment = XCTAttachment(screenshot: shot)
    attachment.name = filename
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
