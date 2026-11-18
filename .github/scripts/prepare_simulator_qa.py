#!/usr/bin/env python3
"""Add explicit test inputs to disposable CI builds of BOTH v5 and v6.

No reader/layout code is patched. UserDefaults must be written inside the app's
sandbox, and iPad test orientation is requested through public UIWindowScene
geometry APIs. Normal builds and launches do not receive these test inputs.
"""
from pathlib import Path

app = Path('ios/Runner/AppDelegate.swift')
text = app.read_text()
marker = '    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)'
assert marker in text
seed = '''    // CI-only launch inputs; inserted by prepare_simulator_qa.py.
    let qa = ProcessInfo.processInfo.environment
    if qa["MUSHAF_QA_TEST"] == "1", let raw = qa["MUSHAF_QA_ZOOM"],
       let zoom = Double(raw), zoom >= 0.6, zoom <= 1.0 {
      let defaults = UserDefaults.standard
      defaults.set(zoom, forKey: "flutter.quran_single_page_scale")
      defaults.set(zoom, forKey: "flutter.quran_landscape_page_scale")
      defaults.set(4, forKey: "flutter.CurrentPage1")
      defaults.set(false, forKey: "flutter.reader_controls_arrow_only")
      defaults.set(true, forKey: "flutter.review_prompt_rate_chosen")
      defaults.synchronize()
    }
'''
app.write_text(text.replace(marker, seed + marker, 1))

scene = Path('ios/Runner/SceneDelegate.swift')
text = scene.read_text()
marker = '    UIApplication.shared.isIdleTimerDisabled = true\n'
assert marker in text
orientation = '''    // CI-only orientation stimulus; the real reader handles the resize.
    let qa = ProcessInfo.processInfo.environment
    if #available(iOS 16.0, *), qa["MUSHAF_QA_TEST"] == "1",
       let desired = qa["MUSHAF_QA_ORIENTATION"], !desired.isEmpty,
       let windowScene = scene as? UIWindowScene {
      let mask: UIInterfaceOrientationMask = desired == "landscape" ? .landscapeLeft : .portrait
      var qaGeometryError = ""
      let writeState: (String) -> Void = { status in
        let root = self.window?.rootViewController
        let state: [String: Any] = [
          "desired": desired, "status": status,
          "error": qaGeometryError,
          "interfaceOrientation": windowScene.interfaceOrientation.rawValue,
          "supportedMask": root.map { Int($0.supportedInterfaceOrientations.rawValue) } ?? -1,
          "sceneSize": [windowScene.coordinateSpace.bounds.width, windowScene.coordinateSpace.bounds.height],
          "rootSize": root.map { [$0.view.bounds.width, $0.view.bounds.height] } ?? [],
          "activation": windowScene.activationState.rawValue,
          "rootType": root.map { String(describing: type(of: $0)) } ?? "nil"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state),
           let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
          try? data.write(to: folder.appendingPathComponent("reader-qa-native.json"), options: .atomic)
        }
      }
      for delay in [1.0, 3.0, 5.0, 10.0, 15.0] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
          self.window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
          windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            qaGeometryError = String(describing: error)
            writeState("orientation request failed")
          }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            writeState("after orientation request at " + String(delay))
          }
        }
      }
    }
'''
scene.write_text(text.replace(marker, marker + orientation, 1))

# Reminder setup is unrelated to reader layout. A delayed system permission
# alert covered otherwise valid screenshots, including identical v5/v6 frames.
# Disable that optional startup service only in these disposable QA copies.
main = Path('lib/main.dart')
text = main.read_text()
marker = '  scheduleDeferredReminders(ReminderNotifications.initialize);'
assert marker in text
main.write_text(text.replace(marker, '  // CI reader QA: optional reminder setup omitted.', 1))
print('Prepared CI-only zoom/orientation inputs and omitted optional reminder setup; reader layout code unchanged.')
