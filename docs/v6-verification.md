# v6 layout and verification contract

Work stays on `v6`. No merge to `main` until final required checks pass.

## Page sizing

On the Duo cover and continuous open portrait display, a single page occupies
the unobstructed horizontal band at every toolbar zoom. Height is the root app
viewport height times zoom (70–100%). The page is vertically centred. At 100%
it extends behind the floating controls and home indicator. The collapsed iOS
tab ends 16 logical points above the app bottom. Expanded controls clear the
larger of the bottom safe inset and 16 points.

In continuous unfolded landscape, each page is `(readingWidth - 1) / 2 × zoom`
wide (60–100%). The one-point gutter stays fixed. The two proportional pages
share a top-aligned vertical scroll viewport. Half-open book pages use equal
proportional fits in their separate physical panels. Folded landscape,
tabletop, regular phones and the native iPad compatibility path retain their
previous sizing. Navigation, selection and audio controls overlay the reader.

The limited native check on v6 is **Proven Duo and iPad mini visual check**.
It builds one simulator app with `READER_LAYOUT_QA`. The Duo artifact contains
the eight zoom endpoints plus the folded collapsed tab and the same landscape
spread after a real swipe. The mini artifact contains both 80% portrait frames,
including the later settled capture. A Linux job assembles the comparison sheet
from verified originals. Each endpoint pairs the PNG with stable measured
geometry on both sides of capture. The verifier reconstructs the reading area
from raw insets, display features and native division frames. The scroll extent,
page order, visible paper edges and measured navigation footprint are checked.

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
