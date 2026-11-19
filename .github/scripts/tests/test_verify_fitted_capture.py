from datetime import datetime, timezone
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_fitted_capture as capture

rect = capture.rect
ASPECT = 721 / 1058


def snapshot(posture="duo-folded", z=1, bottom=False):
    mode = capture.MODES[posture]
    folded = posture == "duo-folded"
    w, h = (466, 678) if folded else (669, 951) if mode == "single" else (951, 669)
    pad = dict(left=0, right=84 if folded else 0, top=0, bottom=34)
    native = dict(
        viewport=dict(width=w, height=h), divisions=[], closed=folded, isIPad=posture == "ipad-mini"
    )
    safe = [rect(0, 0, w - pad["right"], h - 34)]
    band = safe[0]
    if mode == "dualScreenBook":
        native["divisions"] = [dict(rect(400, 0, 24, h), active=True)]
        safe = [rect(0, 0, 400, h - 34), rect(424, 0, w - 424, h - 34)]
    reading = band
    scroll = None
    if mode == "single":
        sizing = "portraitHeight"
        reading = rect(0, 0, band["width"], h)
        regions = [reading]
        pages = {"4": rect(0, h * (1 - z) / 2, band["width"], h * z)}
    elif mode == "spread":
        sizing = "spreadWidth"
        half = (w - 1) / 2
        width, height = half * z, half * z / ASPECT
        maximum = max(0, height - (h - 34))
        offset = maximum if bottom else 0
        regions = [dict(band, width=half), dict(band, left=half + 1, width=half)]
        scroll = dict(viewport=band, min=0, max=maximum, offset=offset, settled=True)
        pages = {
            "4": rect(half + 1, -offset, width, height),
            "5": rect(half - width, -offset, width, height),
        }
    else:
        sizing = "regionFit"
        regions = safe
        width = min(400, (h - 34) * ASPECT) * z
        height = width / ASPECT
        pages = {
            str(p): rect(r["left"] + (r["width"] - width) / 2, (r["height"] - height) / 2, width, height)
            for p, r in zip([5, 4], regions)
        }
    tab = (
        rect((band["width"] - 72) / 2, h - 40, 72, 24)
        if mode == "single"
        else rect(w - 26, h / 2 - 36, 22, 72)
    )
    return dict(
        viewport=dict(width=w, height=h),
        pixelRatio=1,
        mode=mode,
        fit=not native["isIPad"],
        zoom=z,
        focusedPage=4,
        edition="indopak_tajweed",
        safeRegions=safe,
        scroll=scroll,
        timestamp="2026-11-19T11:00:02Z" if bottom else "2026-11-19T11:00:01Z",
        navigation=tab,
        navigationExpanded=False,
        controls={"Open navigation": tab},
        readingBounds=reading,
        regions=regions,
        pages=pages,
        sizing=sizing,
        padding=pad,
        viewPadding=pad.copy(),
        frameworkFeatures=[],
        native=native,
    )


class CaptureTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.png = Path(directory.name) / "reader.png"
        self.metadata = self.png.with_suffix(".layout.json")

    def save(self, frame, blank=False):
        image = Image.new("RGB", tuple(frame["viewport"].values()), "black")
        paper = Image.new("RGB", image.size, "black")
        draw = ImageDraw.Draw(paper)
        if not blank:
            for page in frame["pages"].values():
                l, t, r, b = map(round, capture.bounds(page))
                draw.rectangle((l, t, r - 1, b - 1), fill="white")
                draw.rectangle((l + 12, t + 12, r - 13, b - 13), fill="#252525")
        clip = tuple(map(round, capture.bounds(frame["readingBounds"])))
        image.paste(paper.crop(clip), clip)
        draw = ImageDraw.Draw(image)
        draw.rectangle(capture.bounds(frame["navigation"]), fill="#303030")
        tab = frame["controls"].get("Open navigation")
        if tab:
            x, y = tab["left"] + tab["width"] / 2, tab["top"] + tab["height"] / 2
            draw.line([(x - 4, y + 2), (x, y - 2), (x + 4, y + 2)], fill="white", width=2)
        image.save(self.png)
        self.metadata.write_text(json.dumps(frame))

    def test_all_endpoints(self):
        for posture, mode in capture.MODES.items():
            for zoom in [0.8] if posture == "ipad-mini" else [0.7 if mode == "single" else 0.6, 1]:
                with self.subTest(posture=posture, zoom=zoom):
                    frame = snapshot(posture, zoom)
                    self.save(frame)
                    self.assertTrue(
                        capture.verify(self.png, self.metadata, 100 * zoom, mode, posture=posture)[
                            "verified"
                        ]
                    )

    def test_fresh_scrolled_capture_uses_visible_edges(self):
        before = snapshot("duo-unfolded-wide")
        after = snapshot("duo-unfolded-wide", bottom=True)
        self.save(after)
        capture.verify(
            self.png,
            self.metadata,
            100,
            "spread",
            posture="duo-unfolded-wide",
            phase="bottom",
            before=before,
        )
        for error in (
            "timestamp",
            "page turn",
            "one stationary leaf",
            "no movement",
            "short extent",
            "unsettled",
        ):
            with self.subTest(error=error), self.assertRaises(AssertionError):
                bad = copy.deepcopy(after)
                if error == "timestamp":
                    bad["timestamp"] = before["timestamp"]
                if error == "page turn":
                    bad["pages"] = {str(int(p) + 2): v for p, v in bad["pages"].items()}
                if error == "one stationary leaf":
                    bad["pages"]["5"]["top"] = 0
                if error == "no movement":
                    bad["scroll"]["offset"] = 0
                if error == "short extent":
                    bad["scroll"]["max"] /= 2
                if error == "unsettled":
                    bad["scroll"]["settled"] = False
                capture.check_geometry(bad, "duo-unfolded-wide", "bottom")
                capture.check_pair(before, bad, "bottom")

    def test_wrong_sizing_or_raw_geometry(self):
        for error in (
            "proportional",
            "narrow at minimum",
            "safe height",
            "dock trim",
            "double right inset",
            "stale native",
            "hidden tab",
            "wrong zoom",
            "missing page",
            "blank",
            "wrong display",
        ):
            with self.subTest(error=error), self.assertRaises(AssertionError):
                data = snapshot(z=0.7 if error == "narrow at minimum" else 1)
                page = data["pages"]["4"]
                if error == "proportional":
                    page["height"] = page["width"] / ASPECT
                if error == "narrow at minimum":
                    page["width"] *= 0.7
                if error == "safe height":
                    page["height"] -= 34
                if error == "dock trim":
                    data["readingBounds"]["height"] -= 100
                    page["height"] -= 100
                if error == "double right inset":
                    for r in [data["safeRegions"][0], data["readingBounds"], page]:
                        r["width"] -= 84
                if error == "stale native":
                    data["native"]["viewport"]["width"] -= 50
                if error == "hidden tab":
                    data["controls"]["Open navigation"]["top"] -= 34
                if error == "missing page":
                    data["pages"].clear()
                self.save(data, blank=error == "blank")
                if error == "wrong display":
                    Image.new("RGB", (100, 100)).save(self.png)
                capture.verify(
                    self.png,
                    self.metadata,
                    70 if error in ("wrong zoom", "narrow at minimum") else 100,
                    "single",
                    posture="duo-folded",
                    phase="collapsed",
                )

    def test_landscape_fit_cap_and_missing_scroll(self):
        for error in ("height cap", "no scroll", "dock trim"):
            with self.subTest(error=error), self.assertRaises(AssertionError):
                data = snapshot("duo-unfolded-wide")
                if error == "height cap":
                    for p in data["pages"].values():
                        p.update(width=635 * ASPECT, height=635)
                if error == "no scroll":
                    data["scroll"] = None
                if error == "dock trim":
                    data["readingBounds"] = dict(data["readingBounds"], width=820)
                capture.check_geometry(data, "duo-unfolded-wide")

    def test_hinge_and_raw_divisions(self):
        for error in ("cross hinge", "overflow panel", "missing division"):
            with self.subTest(error=error), self.assertRaises(AssertionError):
                data = snapshot("duo-half-open-book")
                if error == "cross hinge":
                    data["pages"]["4"]["left"] = 410
                if error == "overflow panel":
                    data["pages"]["5"]["top"] = -10
                if error == "missing division":
                    data["native"]["divisions"].clear()
                capture.check_geometry(data, "duo-half-open-book")

    def test_nav_mask_is_limited_to_measured_footprint(self):
        data = snapshot()
        data.update(
            navigation=rect(0, 550, 382, 94),
            navigationExpanded=True,
            controls={"Collapse navigation": rect(155, 550, 72, 24)},
        )
        self.save(data)
        capture.verify(self.png, self.metadata, 100)
        image = Image.open(self.png)
        ImageDraw.Draw(image).rectangle((0, 0, 381, 5), fill="black")
        image.save(self.png)
        with self.assertRaisesRegex(AssertionError, "missing paper edge"):
            capture.verify(self.png, self.metadata, 100)

    def test_state_and_freshness(self):
        data = snapshot()
        after = datetime(2026, 11, 19, 11, 0, 2, tzinfo=timezone.utc).timestamp()
        with self.assertRaisesRegex(AssertionError, "stale rendered"):
            capture.assert_capture_state(data, 100, "single", after)
        with self.assertRaises(AssertionError):
            capture.check_posture(data, "duo-unfolded-portrait", None)
        with self.assertRaises(AssertionError):
            capture.check_posture(
                data, "duo-folded", dict(activeScreen="main", hingeAngle=180, orientation="portrait")
            )
        with self.assertRaisesRegex(AssertionError, "reading mode"):
            capture.assert_capture_state(data, 100, "spread")
