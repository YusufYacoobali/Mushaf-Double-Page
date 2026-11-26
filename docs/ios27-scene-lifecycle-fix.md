# iOS 27 UIScene launch crash — root cause and migration

## Evidence from the failed Duo run

GitHub Actions run 44120715336, artifact 14346873361, includes three
Runner crash reports at 16:13:54, 16:16:08 and 16:18:59 (17 November 2026).
Each is EXC_BREAKPOINT / SIGTRAP on the main thread at
`UIKitCore ___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`.
This is Apple's deliberate iOS 27 failure for an app linked against the
iOS 27 SDK without a UIScene manifest.

The app *was* installed and launched, so repeatedly delaying `simctl launch`
cannot resolve it. The missing Quran page files and home-screen screenshots
were consequences of this crash, not proof of a Firebase download problem.

## App fix

* Add the UIWindowScene application configuration to Runner/Info.plist.
* Use FlutterSceneDelegate for scene events, including plugin forwarding.
* Move generated plugin registration and the iPad detection method channel
  to FlutterImplicitEngineDelegate.didInitializeImplicitFlutterEngine.
* Preserve the reader's keep-awake policy with sceneDidBecomeActive and
  sceneWillResignActive instead of UIApplicationDelegate UI events.
* Keep single-window operation, current page selection, iOS deployment target,
  Firebase configuration, content download and audio playback untouched.

Based on the official Flutter UIScene migration, available since Flutter
3.38, and the Apple UIKit iOS 27 requirements.

## Release gate

Run full Flutter tests and an unsigned iOS simulator build on Xcode 27;
then launch the actual app on the iPhone Duo simulator, not merely compile.
Confirm there are no new Runner crashes, and verify that Quran page images
are available and the actual reader is visible before collecting zoom shots.
