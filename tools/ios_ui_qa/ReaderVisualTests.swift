import XCTest
import Vision
import UIKit
import ImageIO

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
    try dismissVisibleNotification(reader)
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
    try dismissVisibleNotification(reader)
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
  private func dismissVisibleNotification(_ reader: XCUIApplication) throws {
    // Only the two seeded 100% iPad endpoint tests use this optical guard.
    // An absent AX alert is insufficient: inspect genuine screen pixels and
    // touch only the observed denial button of this app's notification prompt.
    print("Notification optical check on simulator " +
          (ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown"))
    var clearFrames = 0
    var taps = 0
    for attempt in 0..<4 {
      let shot = XCUIScreen.main.screenshot()
      let attachment = XCTAttachment(screenshot: shot)
      attachment.name = "notification-optical-\(attempt)"
      attachment.lifetime = .keepAlways
      add(attachment)
      let image = shot.image
      let pixels = try XCTUnwrap(image.cgImage, "notification: screenshot has no pixels")
      // UIImage and CGImagePropertyOrientation have different raw values.
      let orientation: CGImagePropertyOrientation
      let swapsAxes: Bool
      switch image.imageOrientation {
      case .up: orientation = .up; swapsAxes = false
      case .upMirrored: orientation = .upMirrored; swapsAxes = false
      case .down: orientation = .down; swapsAxes = false
      case .downMirrored: orientation = .downMirrored; swapsAxes = false
      case .left: orientation = .left; swapsAxes = true
      case .leftMirrored: orientation = .leftMirrored; swapsAxes = true
      case .right: orientation = .right; swapsAxes = true
      case .rightMirrored: orientation = .rightMirrored; swapsAxes = true
      @unknown default:
        XCTFail("notification: unsupported screenshot orientation")
        return
      }
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["en-US"]
      request.usesLanguageCorrection = false
      try VNImageRequestHandler(cgImage: pixels, orientation: orientation, options: [:]).perform([request])
      let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
      let lines = candidates.map { $0.string }
      let text = lines.joined(separator: " ").lowercased()
      let compact = text.replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
      let denials: [CGRect] = try candidates.compactMap { candidate in
        // Vision may put both button titles on one line. Use the exact denial
        // substring's rectangle, never the centre of a combined line.
        guard let range = candidate.string.range(of: "\\bdon['’]?t\\s+allow\\b",
                                                options: [.regularExpression, .caseInsensitive]) else { return nil }
        return try XCTUnwrap(candidate.boundingBox(for: range),
                             "notification: denial text has no bounding box").boundingBox
      }
      let whiteFraction = try nearWhiteFraction(pixels)
      let diagnostic = XCTAttachment(string: "nearWhiteFraction=\(whiteFraction)\n" + lines.joined(separator: "\n"))
      diagnostic.name = "notification-optical-\(attempt)-text"
      diagnostic.lifetime = .keepAlways
      add(diagnostic)
      let hasDialogText = compact.contains("notifications") || compact.contains("qurandualpage") ||
        compact.contains("dontallow") || text.range(of: "\\ballow\\b", options: .regularExpression) != nil
      if hasDialogText {
        guard compact.contains("qurandualpage"), compact.contains("notifications"),
              denials.count == 1, taps < 2 else {
          XCTFail("notification: unexpected or unresolved dialog: " + lines.joined(separator: " | "))
          return
        }
        let box = denials[0]
        guard box.width > 0, box.height > 0, box.minX >= 0, box.minY >= 0,
              box.maxX <= 1, box.maxY <= 1 else {
          XCTFail("notification: invalid observed denial bounds: \(box)")
          return
        }
        let frame = reader.frame
        let width = CGFloat(swapsAxes ? pixels.height : pixels.width)
        let height = CGFloat(swapsAxes ? pixels.width : pixels.height)
        guard frame.width > 0, frame.height > 0, abs(frame.minX) < 1, abs(frame.minY) < 1,
              abs(frame.width / frame.height - width / height) < 0.002 else {
          XCTFail("notification: screenshot and full-screen reader coordinate frames disagree")
          return
        }
        // Vision boxes start at the bottom-left; XCTest starts at the top-left.
        reader.coordinate(withNormalizedOffset: CGVector(dx: box.midX, dy: 1 - box.midY)).tap()
        taps += 1
        clearFrames = 0
        Thread.sleep(forTimeInterval: 1)
      } else {
        // On these 100% endpoints the real page has abundant white paper.
        // The observed permission sheet dims it to ~204; clear references
        // retain >26% near-white pixels even with bilinear downsampling.
        XCTAssertGreaterThanOrEqual(whiteFraction, 0.20,
          "notification: no clear white page; empty OCR cannot prove dismissal")
        clearFrames += 1
        if clearFrames == 2 { return }
        Thread.sleep(forTimeInterval: 0.7)
      }
    }
    XCTFail("notification: could not establish two clear reader screenshots")
  }

  private func nearWhiteFraction(_ image: CGImage) throws -> Double {
    let side = 128
    var samples = [UInt8](repeating: 0, count: side * side * 4)
    return try samples.withUnsafeMutableBytes { bytes in
      let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
        "notification: cannot sample screenshot pixels")
      context.interpolationQuality = .low
      context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
      let pixels = bytes.bindMemory(to: UInt8.self)
      let white = stride(from: 0, to: pixels.count, by: 4).filter {
        pixels[$0] >= 245 && pixels[$0 + 1] >= 245 && pixels[$0 + 2] >= 245
      }.count
      return Double(white) / Double(side * side)
    }
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
