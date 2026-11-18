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
      DispatchQueue.main.async {
        self.window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
      }
    }
'''
scene.write_text(text.replace(marker, marker + orientation, 1))
print('Prepared CI-only native zoom and orientation inputs; reader code unchanged.')
