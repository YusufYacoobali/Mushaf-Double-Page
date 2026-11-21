# Build Mushaf for iPhone Duo with Xcode 27 (without a new Mac)

The manual workflow is [Mushaf iOS 27 cloud release](../.github/workflows/mushaf-ios27-appstore.yml) on the repository's **main** branch. It checks out **v7** by default; it does not publish on pushes, edit v7, or change your local Xcode. Use this for future branches by changing the `source_ref` input.

## First: verify the native SDK integration (no Apple credentials)

1. In GitHub, open **Actions → Mushaf iOS 27 cloud release → Run workflow**.
2. Select workflow branch **main**, `source_ref = v7`, `mode = verify`.
3. Run it. It checks that Xcode and the iOS SDK are **27.1 or newer**, the iPhoneOS **Release** build contains `MUSHAF_DUO_SDK`, and the Flutter app compiles **without code signing**. This does **not** upload anything to Apple.

Note: GitHub requires manually dispatched workflows to exist on the default branch. The workflow itself therefore lives on `main`; the `source_ref` field chooses which app version is built.

## One-time Apple setup for signed builds and upload

### A. Create an App Store Connect API key

1. Open [App Store Connect](https://appstoreconnect.apple.com/) → **Users and Access → Integrations → App Store Connect API**.
2. Generate a **team API key** with **App Manager** access. Download its `AuthKey_XXXXXXXXXX.p8` file once; Apple does not permit redownloading.
3. Note the **Issuer ID** and **Key ID** shown next to the key.
4. In App Store Connect → **My Apps → Quran Dual Page → App Information**, copy the actual **Bundle ID** of the *existing* app. It must match the app users have installed. Do not assume that the repository's current `com.example.mushafTwoPage` identifier is correct.

### B. Add repository variables

Open [Mushaf GitHub Actions variables](https://github.com/YusufYacoobali/Mushaf-Double-Page/settings/variables/actions), then create:

| Variable | Value |
| --- | --- |
| `IOS_BUNDLE_ID` | The exact existing App Store Connect Bundle ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from the team API key |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Key ID from the team API key |
| `APP_STORE_APPLE_ID` (optional) | `6757914006` (this app's public Apple ID, already the workflow default) |

### C. Add repository secrets

Open [Mushaf GitHub Actions secrets](https://github.com/YusufYacoobali/Mushaf-Double-Page/settings/secrets/actions) and create:

- `APP_STORE_CONNECT_PRIVATE_KEY`: Paste the **full text contents** of the downloaded `.p8` file, including the BEGIN/END lines.
- `CERTIFICATE_PRIVATE_KEY`: A **persistent RSA private key** used to create/reuse the Apple distribution certificate. Generate it **once** on your current Mac:

  ```bash
  ssh-keygen -t rsa -b 2048 -m PEM -f "$HOME/mushaf-ci-cert-key" -q -N ""
  pbcopy < "$HOME/mushaf-ci-cert-key"
  ```

  Paste the clipboard contents into the GitHub secret. Keep the key securely backed up and **never commit or paste either private key into source code, a GitHub issue or ChatGPT**. The corresponding `.pub` file is not required. Reuse this same secret for future runs instead of generating a fresh certificate private key each release.

The workflow uses these credentials with [Codemagic CLI tools](https://docs.flutter.dev/deployment/ios) to fetch/create the App Store distribution certificate and provisioning profile in the cloud, use a temporary keychain, and export the signed IPA. No `.p12` or local Xcode 27 installation is needed. If Apple refuses to create a new distribution certificate because your team is at its certificate limit, reuse/export a suitable existing signing key or manage obsolete certificates in Apple Developer.

## Running a signed build or uploading

1. Go to **Actions → Mushaf iOS 27 cloud release → Run workflow** on **main**.
2. Leave `source_ref = v7`. Choose `mode = build` to create a signed IPA as a seven-day GitHub artifact without uploading, or choose `mode = upload` to upload it directly to **App Store Connect** for TestFlight processing.
3. You can leave **app_version** blank to use `pubspec.yaml` (`1.7.0` on v7). The workflow queries Apple and selects a new build number.
4. After an upload succeeds and Apple processes the build, open App Store Connect → **TestFlight** and select it for testing. To release publicly, select the processed build on the app version and follow Apple's regular App Review steps. The workflow **does not automatically submit for App Review or distribute to external testers**.

## Important compatibility and configuration notes

- **iOS 15 minimum:** Apple's Xcode 27 supported deployment target starts at iOS 15. The workflow raises the deployment target in the **temporary GitHub checkout only**. Releasing that build means users still on iOS 13/14 cannot install the new version; their existing installed version is not changed. Decide whether that trade-off is acceptable before submitting to production.
- **Firebase bundle mismatch:** v7 still contains `com.example.mushafTwoPage` in `lib/firebase_options.dart` and `ios/Runner/GoogleService-Info.plist`. If your real App Store bundle ID differs, **verify/configure the correct iOS Firebase app** (including regenerated `flutterfire configure` output and the matching GoogleService plist) *on the source branch before production upload*. The cloud workflow warns about this discrepancy, but does not fabricate Firebase credentials or silently alter them.
- **SDK and actual device:** Compiling with Xcode 27.1+ is necessary to enable the conditional Duo native-region API, but a successful upload is not proof of the physical Duo layout. First send the TestFlight build to the Duo user and confirm the top/bottom letterboxing is gone at 100%.
- GitHub's `xcode-27` runner can update to later Xcode 27.x releases. The workflow checks the installed compiler and SDK at runtime; it does not rely on the runner label alone.
- For release failures inspect the failed step in GitHub Actions. If uploading fails with a bundle-ID or entitlement error, cross-check `IOS_BUNDLE_ID` and the App Store profile. Do not post secrets in GitHub issues or logs.

Useful references: [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios), [GitHub manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow), [Apple Xcode SDK requirements](https://developer.apple.com/xcode/system-requirements/).
