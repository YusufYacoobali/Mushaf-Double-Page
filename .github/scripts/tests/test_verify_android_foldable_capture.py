"""Negative evidence checks for Samsung-dimension Android layout captures.

The paper drawn here is a synthetic unit fixture, never a native QA artifact.
"""

import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_android_foldable_capture as capture

ASPECT = 721 / 1058
DPR = 420 / 160
STAMP = "2026-11-19T16:00:01Z"


def declaration(profile):
    inner, cover = (
        ((2448, 1848), (1248, 1972)) if profile == "galaxy-z-fold8"
        else ((2256, 2504), (1080, 2520))
    )
    return {
        "schemaVersion": 1,
        "profileId": profile,
        "emulation": {"kind": capture.EMULATION, "os": "stock-android",
                      "oneUi": False, "realSamsungDevice": False},
        "displays": {name: {"width": size[0], "height": size[1], "densityDpi": 420}
                     for name, size in [("inner", inner), ("cover", cover)]},
        "sources": ["unit fixture; never native screenshot evidence"],
        "assumptions": ["420 dpi custom AVD density"],
    }


def snapshot(posture="folded", z=1, profile="galaxy-z-fold8", phase="initial", expanded=False):
    declared = declaration(profile)
    display = declared["displays"]["cover" if posture == "folded" else "inner"]
    pixel_width, pixel_height = display["width"], display["height"]
    if posture in ("folded", "unfolded-portrait"):
        pixel_width, pixel_height = sorted([pixel_width, pixel_height])
    elif posture == "unfolded-landscape":
        pixel_height, pixel_width = sorted([pixel_width, pixel_height])
    w, h = pixel_width / DPR, pixel_height / DPR
    pad = dict(left=0, top=0, right=0, bottom=24)
    features = []
    if posture != "folded":
        vertical = [pixel_width, pixel_height] == [display["width"], display["height"]]
        fold = capture.rect(w / 2, 0, 0, h) if vertical else capture.rect(0, h / 2, w, 0)
        features = [dict(bounds=fold, type="fold", state="postureHalfOpened" if posture == "half-open-book" else "postureFlat")]
    safe = [capture.rect(0, 0, w, h - 24)]
    mode = capture.POSTURES[posture]
    scroll = None
    if mode == "single":
        reading = capture.rect(0, 0, w, h)
        regions = [reading]
        pages = {"6": capture.rect(0, h * (1 - z) / 2, w, h * z)}
        sizing = "portraitHeight"
    elif mode == "spread":
        reading = safe[0]
        half = (w - 1) / 2
        width, height = half * z, half * z / ASPECT
        maximum = max(0, height - reading["height"])
        offset = maximum if phase == "bottom" else 0
        regions = [capture.rect(0, 0, half, h - 24), capture.rect(half + 1, 0, half, h - 24)]
        pages = {"7": capture.rect(half - width, -offset, width, height),
                 "6": capture.rect(half + 1, -offset, width, height)}
        scroll = dict(viewport=reading, min=0, max=maximum, offset=offset, settled=True)
        sizing = "spreadWidth"
    else:
        safe = [capture.rect(0, 0, w / 2, h - 24), capture.rect(w / 2, 0, w / 2, h - 24)]
        regions = copy.deepcopy(safe)
        reading = capture.rect(0, 0, w, h - 24)
        width = min(w / 2, (h - 24) * ASPECT) * z
        height = width / ASPECT
        pages = {p: capture.rect(panel["left"] + (panel["width"] - width) / 2,
                                 (h - 24 - height) / 2, width, height)
                 for p, panel in zip(["7", "6"], regions)}
        sizing = "regionFit"
    portrait_dock = mode == "single" or (mode == "dualScreenBook" and h > w)
    panel = safe[-1]
    tab = (capture.rect(panel["left"] + (panel["width"] - 72) / 2, h - 24 - 24, 72, 24)
           if portrait_dock else capture.rect(w - 26, (h - 24 - 72) / 2, 22, 72))
    navigation = capture.rect(panel["left"] + 10, h - 24 - 80, panel["width"] - 20, 80) if expanded else tab
    data = dict(
        viewport=dict(width=w, height=h), pixelRatio=DPR, padding=pad, viewPadding=pad.copy(),
        frameworkFeatures=features, native=dict(viewport=dict(width=0, height=0), divisions=[], closed=False, isIPad=False),
        mode=mode, sizing=sizing, fit=posture != "folded", zoom=z, focusedPage=6, edition="indopak_tajweed",
        readingBounds=reading, safeRegions=safe, regions=regions, pages=pages, scroll=scroll,
        navigationExpanded=expanded, navigation=navigation,
        controls={"Collapse navigation" if expanded else "Open navigation": tab}, timestamp=STAMP,
    )
    canonical_posture = 1 if posture == "folded" else 2 if posture == "half-open-book" else 3
    state = dict(profile=profile, emulation=capture.EMULATION, requestedPosture=posture,
                 profileMetadata=declared, deviceState="DeviceState{identifier=2, name=OPENED}",
                 emulatorPosture=canonical_posture, emulatorPostureSource="hinge-angle0",
                 hingeAngle={1: 0, 2: 90, 3: 180}[canonical_posture],
                 foregroundPackage=capture.PACKAGE, noSystemDialogs=True,
                 pixelSize=[pixel_width, pixel_height], deviceTimestamp=capture.timestamp(STAMP) + 1,
                 displayDump="unit-test display dump", windowDump="unit-test window dump")
    return data, state


class AndroidCaptureTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.png = Path(directory.name) / "reader.png"
        self.metadata = self.png.with_suffix(".layout.json")

    def save(self, data, blank=False):
        size = tuple(round(data["viewport"][k] * data["pixelRatio"]) for k in ("width", "height"))
        image = Image.new("RGB", size, "black")
        paper = Image.new("RGB", size, "black")
        draw = ImageDraw.Draw(paper)
        if not blank:
            for frame in data["pages"].values():
                l, t, r, b = [round(v * data["pixelRatio"]) for v in capture.bounds(frame)]
                draw.rectangle((l, t, r - 1, b - 1), fill="white")
                draw.rectangle((l + 24, t + 24, r - 25, b - 25), fill="#252525")
        clip = tuple(round(v * data["pixelRatio"]) for v in capture.bounds(data["readingBounds"]))
        image.paste(paper.crop(clip), clip)
        draw = ImageDraw.Draw(image)
        draw.rectangle(tuple(round(v * DPR) for v in capture.bounds(data["navigation"])), fill="#303030")
        tab = data["controls"].get("Open navigation")
        if tab:
            x, y = (tab["left"] + tab["width"] / 2) * DPR, (tab["top"] + tab["height"] / 2) * DPR
            draw.line([(x - 4 * DPR, y + 2 * DPR), (x, y - 2 * DPR), (x + 4 * DPR, y + 2 * DPR)], fill="white", width=4)
        image.save(self.png)
        self.metadata.write_text(json.dumps(data))

    def test_both_shapes_all_postures_use_actual_android_insets(self):
        for profile in capture.PROFILES:
            for posture in capture.POSTURES:
                for zoom in [0.7 if capture.POSTURES[posture] == "single" else 0.6, 1]:
                    with self.subTest(profile=profile, posture=posture, zoom=zoom):
                        data, state = snapshot(posture, zoom, profile)
                        capture.assert_capture_state(data, expected_page=6)  # Generic startup readiness.
                        capture.assert_capture_state(data, zoom * 100, posture)
                        reading = capture.check_geometry(data, posture, state=state)
                        self.assertEqual(data["viewport"]["height"] - capture.bounds(reading)[3],
                                         0 if data["mode"] == "single" else 24)

    def test_blank_or_missing_native_pixels_are_rejected(self):
        data, state = snapshot()
        self.save(data, blank=True)
        with self.assertRaisesRegex(AssertionError, "blank or unrendered"):
            capture.verify(self.png, self.metadata, 100, "folded", state=state)
        self.save(data)
        result = capture.verify(self.png, self.metadata, 100, "folded", state=state)
        self.assertTrue(result["verified"])
        self.assertFalse(result["one_ui_verified"])
        state["pixelSize"][0] -= 1
        with self.assertRaisesRegex(AssertionError, "stale physical display"):
            capture.verify(self.png, self.metadata, 100, "folded", state=state)

    def test_samsung_identity_and_emulation_disclosure_are_required(self):
        data, state = snapshot("unfolded-portrait")
        for mutation in ["pixel", "one-ui", "real-hardware", "wrong-model", "wrong-pixels", "density"]:
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                bad = copy.deepcopy(state)
                if mutation == "pixel": bad["profile"] = "pixel-fold"
                if mutation == "one-ui": bad["profileMetadata"]["emulation"]["oneUi"] = True
                if mutation == "real-hardware": bad["profileMetadata"]["emulation"]["realSamsungDevice"] = True
                if mutation == "wrong-model": bad["profileMetadata"]["profileId"] = "galaxy-z-fold8-ultra"
                if mutation == "wrong-pixels": bad["profileMetadata"]["displays"]["inner"]["width"] += 20
                if mutation == "density": bad["profileMetadata"]["displays"]["inner"]["densityDpi"] += 20
                capture.check_geometry(data, "unfolded-portrait", state=bad)

    def test_real_fold_signal_sensor_and_foreground_are_required(self):
        data, state = snapshot("half-open-book")
        for mutation in ["no-feature", "flat-feature", "wrong-angle", "wrong-posture", "wrong-app", "popup", "no-sensor"]:
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                bad, native = copy.deepcopy(data), copy.deepcopy(state)
                if mutation == "no-feature": bad["frameworkFeatures"] = []
                if mutation == "flat-feature": bad["frameworkFeatures"][0]["state"] = "postureFlat"
                if mutation == "wrong-angle": native["hingeAngle"] = 180
                if mutation == "wrong-posture": native["emulatorPosture"] = 3
                if mutation == "wrong-app": native["foregroundPackage"] = "com.android.launcher"
                if mutation == "popup": native["noSystemDialogs"] = False
                if mutation == "no-sensor": native.pop("hingeAngle")
                capture.check_geometry(bad, "half-open-book", state=native)

    def test_stale_wrong_page_and_wrong_zoom_fail(self):
        data, state = snapshot("unfolded-landscape")
        for mutation in ["page", "neighbor", "zoom", "after", "native-clock"]:
            with self.subTest(mutation=mutation), self.assertRaises(AssertionError):
                bad, native = copy.deepcopy(data), copy.deepcopy(state)
                after = None
                if mutation == "page": bad["focusedPage"] = 4
                if mutation == "neighbor": bad["pages"]["5"] = bad["pages"].pop("7")
                if mutation == "zoom": bad["zoom"] = 0.7
                if mutation == "after": after = capture.timestamp(STAMP) + 1
                if mutation == "native-clock": native["deviceTimestamp"] += 500
                capture.assert_capture_state(bad, 100, "unfolded-landscape", after)
                capture.check_geometry(bad, "unfolded-landscape", state=native)

    def test_android_book_must_not_inherit_ios_bottom_extension(self):
        data, state = snapshot("half-open-book")
        for panel in data["regions"]: panel["height"] += 24
        data["readingBounds"]["height"] += 24
        with self.assertRaisesRegex(AssertionError, "Android reading bounds"):
            capture.check_geometry(data, "half-open-book", state=state)

    def test_bottom_endpoint_can_have_real_overflow_or_zero_range(self):
        for profile in capture.PROFILES:
            before, _ = snapshot("unfolded-landscape", profile=profile)
            after, state = snapshot("unfolded-landscape", profile=profile, phase="bottom")
            after["timestamp"] = "2026-11-19T16:00:02Z"
            capture.check_geometry(after, "unfolded-landscape", phase="bottom", state=state)
            capture.check_pair(before, after, "bottom")
            if profile == "galaxy-z-fold8-ultra":
                self.assertEqual(after["scroll"]["max"], 0)
            else:
                self.assertGreater(after["scroll"]["max"], 0)
                after["pages"]["7"]["top"] += 2
                with self.assertRaisesRegex(AssertionError, "leaves did not scroll together"):
                    capture.check_pair(before, after, "bottom")

    def test_collapse_requires_real_transition_and_fixed_paper(self):
        before, _ = snapshot(expanded=True)
        after, state = snapshot()
        after["timestamp"] = "2026-11-19T16:00:02Z"
        self.save(after)
        capture.verify(self.png, self.metadata, 100, "folded", state=state,
                       phase="collapsed", before=before)
        after["pages"]["6"]["top"] += 1
        with self.assertRaisesRegex(AssertionError, "collapse moved paper"):
            capture.check_pair(before, after, "collapsed")


if __name__ == "__main__":
    unittest.main()
