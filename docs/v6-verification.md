# v6 layout and verification contract

Work stays on `v6`. No merge to `main` until final required checks pass.

## Page sizing

For Duo/foldable readers, **100% is the largest complete, undistorted page that
fits the usable reading area**. Compute the fit from both width and height,
using the actual viewport, safe areas, native hinge regions and measured dock
bounds. The limiting dimension wins. Smaller percentages multiply this fitted
100% size; they do not change the image's aspect ratio. Both book pages use the
same size, limited by the smaller available panel. The measured expanded dock
footprint remains reserved during automatic hiding to avoid moving text.

**iPad page sizing keeps v5 behaviour.** Only the requested landscape dock
centring changes. Regular non-foldable phone sizing is also preserved.

QA simulator builds enable `READER_LAYOUT_QA`. This records actual rendered
page/control rectangles in the simulator's Documents directory. Capture checks
cross-check those rectangles against the PNG's visible paper edges, contrast,
aspect ratio, maximum fit, zoom, page count and book ordering. A PNG file or a
visible zoom label alone is never a visual pass. Ordinary builds do not record
these diagnostics.

## Verification levels

- Every code push: `Flutter release checks` runs analysis, Flutter tests and
  build-cache compatibility tests on Linux. It does not start simulators or
  compile iOS unless explicitly requested through its manual input.
- Development: manually run `iPhone Duo visual check`, branch `v6`, level
  `targeted`. Select a single device/posture and `layout`, `navigation`, `zoom`
  or `all`. `duo-smoke` captures the four postures at 100% and checks the book
  turn. A zoom case exercises every available five-percent step.
- Before release: select level `full`. It gates Duo, then iPad mini, then the
  11-inch and 13-inch iPads, followed by the unsigned release build. Independent
  iPad layout evidence is retained even when a control interaction fails.

Use this development order: fast checks → compatible simulator build → Duo
smoke/book fit/order/gesture → mini portrait/landscape → larger iPads → inspect
the actual images. Run final full verification only after focused cases pass.

## Build and data reuse

The application-input tree and exact Flutter/Xcode/SDK/architecture/build
configuration identify each simulator build. QA-only changes do not change
the application identity. Build manifests record the original source commit,
archive SHA-256 and producer job. Cache reuse verifies all of these and checks
that the producer build job succeeded, including all job attempts. Cancelled
visual workflows do not automatically invalidate a separately successful build.

`auto` builds only on a compatible-cache miss; `reuse-only` fails clearly on a
miss; `rebuild` deliberately bypasses the cache. Devices all download the one
shared compatible app artifact. There are no pinned run IDs for reuse.

Each test starts a fresh isolated simulator. Real downloaded Quran pages are
checksum-verified before reuse, including the app's original data-version
marker. No Quran assets or production data are changed. v5 layout screenshots
are cached by reference-build identity, exact device/runtime and capture profile.
Zoom/control-only harness changes do not invalidate this baseline.

## Failures and reporting

Simulator operations have explicit timeouts and per-operation logs/results.
Artifacts are uploaded even after failures. Reports identify boot, install,
launch, download, rotation, navigation, zoom, gesture or screenshot failures.
Layout and controls are separate XCTest cases. Rerun the failed device/case
using the compatible build; do not restart an unrelated matrix. Per-device
concurrency serializes runs without cancelling an expensive active run.

The final report must link workflows and actual screenshots, distinguish app
defects from harness problems, state the v5 iPad geometry comparison, and give
workflow/device-run counts and approximate allocated runner minutes. Stop
changing verification after it succeeds unless an actual defect is found.
