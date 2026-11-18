import SwiftUI

// A separate XCTest host, never bundled with or injected into the reader.
@main
struct QAHost: App {
  var body: some Scene {
    WindowGroup { Text("Reader simulator test harness") }
  }
}
