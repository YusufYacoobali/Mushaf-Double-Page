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

    XCUIDevice.shared.orientation = .landscapeLeft
    waitForOrientation(reader, landscape: true)
    dismissNotification()
    let zoom = reader.staticTexts["70%"]
    if !zoom.exists || !zoom.isHittable {
      let tab = reader.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Open navigation")).firstMatch
      if tab.waitForExistence(timeout: 2) {
        tab.tap()
      } else {
        let frame = reader.frame
        reader.coordinate(withNormalizedOffset: CGVector(dx: (frame.width - 15) / frame.width, dy: 0.5)).tap()
      }
    }
    Thread.sleep(forTimeInterval: 0.5)
    try capture("landscape.png")
    XCTAssertTrue(zoom.waitForExistence(timeout: 3), "Landscape reader must expose its original 70% zoom")
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
