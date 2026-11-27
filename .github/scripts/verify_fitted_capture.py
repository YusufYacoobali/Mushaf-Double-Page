#!/usr/bin/env python3
"""Check the measured reader and the visible paper against native inputs."""

from datetime import datetime
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps, ImageStat


MODES = {
    "duo-folded": "single",
    "duo-unfolded-portrait": "single",
    "duo-unfolded-wide": "spread",
    "duo-half-open-book": "dualScreenBook",
    "ipad-mini": "single",
    "ipad-mini-landscape": "spread",
}


def rect(left, top, width, height):
    return dict(left=left, top=top, width=width, height=height)


def bounds(r):
    return r["left"], r["top"], r["left"] + r["width"], r["top"] + r["height"]


def same_rect(actual, expected):
    return all(math.isclose(actual[k], expected[k], abs_tol=0.5) for k in expected)


def assert_capture_state(data, expected_zoom=None, expected_mode=None, after=None, expected_page=None):
    mode = data["mode"]
    assert mode in MODES.values() and (expected_mode is None or mode == expected_mode), (
        "wrong reading mode"
    )
    if expected_zoom is not None:
        assert math.isclose(data["zoom"] * 100, expected_zoom, abs_tol=0.1), "wrong actual rendered zoom"
    if after is not None:
        stamp = datetime.fromisoformat(data["timestamp"].replace("Z", "+00:00"))
        assert stamp.tzinfo and stamp.timestamp() >= after, "stale rendered geometry timestamp"
    assert len(data["pages"]) == (1 if mode == "single" else 2), "wrong rendered page count"
    assert str(data["focusedPage"]) in data["pages"], "focused page missing"
    if expected_page is not None:
        expected_pages = {str(expected_page)}
        if mode != "single":
            expected_pages.add(str(expected_page + 1))
        assert data["focusedPage"] == expected_page and set(data["pages"]) == expected_pages, (
            "wrong requested Quran pages"
        )
    assert data.get("safeRegions"), "missing safe display regions"


def native_panels(data):
    """Partition the raw view once, without trusting the reported reading or panel bounds."""
    w, h = (data["viewport"][k] for k in ("width", "height"))
    pad = data["padding"]
    for source in (pad, data["viewPadding"]):
        assert all(
            math.isfinite(source[k]) and source[k] >= 0 for k in ("left", "top", "right", "bottom")
        )
    panels = [(pad["left"], pad["top"], w - pad["right"], h - pad["bottom"])]
    native = data["native"]
    dividers = [
        f["bounds"]
        for f in data["frameworkFeatures"]
        if f["type"] in ("hinge", "cutout")
        or (f["type"] == "fold" and f["state"] == "postureHalfOpened")
    ]
    if not native["isIPad"]:
        assert all(abs(native["viewport"][k] - data["viewport"][k]) < 1 for k in ("width", "height")), (
            "stale native source viewport"
        )
        dividers.extend(r for r in native["divisions"] if r["active"])
    for divider in dividers:
        x, y, xx, yy = bounds(divider)
        if xx == x and yy == y:
            continue
        result = []
        for l, t, r, b in panels:
            if yy - y > xx - x and y <= t and yy >= b and x < r and xx >= l:
                slices = [(l, t, x, b), (xx, t, r, b)]
            elif xx - x > yy - y and x <= l and xx >= r and y < b and yy >= t:
                slices = [(l, t, r, y), (l, yy, r, b)]
            else:
                slices = [(l, t, r, b)]
            result.extend(s for s in slices if s[0] < s[2] and s[1] < s[3])
        panels = result
    expected = [rect(l, t, r - l, b - t) for l, t, r, b in sorted(panels)]
    assert (
        expected
        and len(data["safeRegions"]) == len(expected)
        and all(same_rect(a, b) for a, b in zip(sorted(data["safeRegions"], key=bounds), expected))
    ), "safe regions disagree with raw native geometry"
    return expected


def check_posture(data, posture, state):
    mode = MODES[posture]
    assert data["mode"] == mode
    w, h = (data["viewport"][k] for k in ("width", "height"))
    assert (w < h) == (mode == "single"), "wrong viewport orientation"
    ipad = posture.startswith("ipad-mini")
    assert data["native"]["isIPad"] == ipad and data["fit"] != ipad
    if not ipad:
        folded = posture == "duo-folded"
        assert data["native"]["closed"] == folded, "native cover state disagrees with requested posture"
        if state is not None:
            angle = state["hingeAngle"]
            assert (state["activeScreen"] == "cover") == folded, "wrong active native screen"
            assert state["orientation"] == ("portrait" if mode == "single" else "landscape")
            if folded:
                assert angle <= 15
            elif mode == "dualScreenBook":
                assert 60 <= angle <= 120
            else:
                assert angle >= 160


def check_geometry(data, posture, phase="initial", state=None):
    check_posture(data, posture, state)
    panels = native_panels(data)
    w, h = (data["viewport"][k] for k in ("width", "height"))
    mode, z = data["mode"], data["zoom"]
    aspect = 2096 / 3008 if data["edition"] == "madani" else 721 / 1058
    pages = sorted(data["pages"].items(), key=lambda item: item[1]["left"])
    assert (
        data["sizing"]
        == {"single": "portraitHeight", "spread": "spreadWidth", "dualScreenBook": "regionFit"}[mode]
    ), "wrong page sizing"
    expanded = data["navigationExpanded"]
    assert isinstance(expanded, bool)
    assert data["navigation"]
    if posture == "duo-folded":
        assert expanded and not {"Open navigation", "Collapse navigation"}.intersection(data["controls"]), (
            "folded dock must stay open without a tab"
        )
        l, t, r, b = bounds(data["navigation"])
        sl, st, sr, sb = bounds(data["native"]["coverStrip"])
        assert max(sl, bounds(panels[0])[2]) <= l < r <= min(sr, w) and st <= t < b <= sb, (
            "folded dock leaves the dedicated strip"
        )
        for ol, ot, oright, ob in map(bounds, data["native"]["coverObstructions"]):
            assert r <= ol or l >= oright or b <= ot or t >= ob, "dock overlaps reserved region"
        for name in ("Zoom in", "Zoom out"):
            assert name in data["controls"], f"missing {name}"
    else:
        tab = data["controls"]["Collapse navigation" if expanded else "Open navigation"]
        assert tab["width"] > 0 and tab["height"] > 0
        if not expanded:
            assert same_rect(data["navigation"], tab), "collapsed footprint differs from tab"
    if mode == "single":
        assert len(panels) == 1
        band = panels[0]
        reading = rect(0, 0, w, h) if posture == "ipad-mini" else rect(band["left"], 0, band["width"], h)
        regions = [reading]
        expected = [dict(reading, top=h * (1 - z) / 2, height=h * z)]
        if not expanded:
            assert math.isclose(bounds(tab)[3], h - 16, abs_tol=0.5), "wrong collapsed tab bottom"
        assert data["scroll"] is None
    else:
        assert int(pages[0][0]) == int(pages[1][0]) + 1, "wrong RTL page order"
        if mode == "spread":
            assert len(panels) == 1
            safe_panel = panels[0]
            # Unfolded Duo renders all the way to the physical bottom edge
            # behind the iOS home swipe indicator. Safe panels and dock remain
            # inset so controls never enter that system gesture area.
            reading = (
                rect(0, 0, w, h)
                if posture == "ipad-mini-landscape"
                else dict(safe_panel, height=h - safe_panel["top"])
                if posture == "duo-unfolded-wide"
                else safe_panel
            )
            region_half = (safe_panel["width"] - 1) / 2
            regions = [
                dict(safe_panel, width=region_half),
                dict(safe_panel, left=safe_panel["left"] + region_half + 1, width=region_half),
            ]
            half = (reading["width"] - 1) / 2
            width = half * z
            height = width / aspect
            scroll = data["scroll"]
            assert scroll and scroll["settled"] and same_rect(scroll["viewport"], reading), (
                "missing settled scroll viewport"
            )
            overflow = max(0, height - reading["height"])
            assert abs(scroll["min"]) <= 0.5 and abs(scroll["max"] - overflow) <= 0.5, (
                "incorrect scroll extent"
            )
            offset = scroll["offset"]
            assert abs(offset - (overflow if phase == "bottom" else 0)) <= 0.5, "wrong scroll endpoint"
            if phase == "bottom":
                assert overflow > 0.5, "no vertical overflow to demonstrate"
            x = reading["left"] + half - width
            inset = max(0, (reading["height"] - height) / 2) if posture == "duo-unfolded-wide" else 0
            top = reading["top"] + inset - offset
            expected = [
                rect(x, top, width, height),
                rect(x + width + 1, top, width, height),
            ]
        else:
            assert len(panels) == 2, "book needs two physical panels"
            left, right = panels
            assert left["top"] == right["top"] and left["height"] == right["height"]
            assert bounds(left)[2] <= right["left"] and int(pages[1][0]) == data["focusedPage"]
            regions = panels
            # Preserve the real hinge and control-safe panels, but do not reserve
            # the home-swipe strip beneath an otherwise unobstructed iOS book.
            obstructions = [r for r in data["native"]["divisions"] if r["active"]]
            obstructions.extend(
                f["bounds"]
                for f in data["frameworkFeatures"]
                if f["type"] in ("hinge", "cutout")
                or (f["type"] == "fold" and f["state"] == "postureHalfOpened")
            )
            def clear_extension(panel):
                l, t, r, b = bounds(panel)
                if abs(b - (h - data["padding"]["bottom"])) > 0.5:
                    return False
                return not any(
                    x < r and xx > l and y < h and yy > b
                    for x, y, xx, yy in map(bounds, obstructions)
                )
            if all(clear_extension(panel) for panel in panels):
                regions = [dict(panel, height=h - panel["top"]) for panel in panels]
            left, right = regions
            reading = dict(left, width=bounds(right)[2] - left["left"])
            width = min(min(p["width"], p["height"] * aspect) for p in regions) * z
            height = width / aspect
            expected = [
                rect(
                    p["left"] + (p["width"] - width) / 2,
                    p["top"] + (p["height"] - height) / 2,
                    width,
                    height,
                )
                for p in regions
            ]
            assert data["scroll"] is None
    assert same_rect(data["readingBounds"], reading), "incorrect reading bounds"
    assert len(data["regions"]) == len(regions) and all(
        same_rect(a, b) for a, b in zip(data["regions"], regions)
    ), "incorrect page regions"
    for (page, actual), target in zip(pages, expected):
        assert same_rect(actual, target), f"page {page} bounds {actual} differ from {target}"
    return reading


def check_pair(before, after, phase):
    for key in (
        "viewport",
        "pixelRatio",
        "edition",
        "safeRegions",
        "readingBounds",
        "sizing",
        "focusedPage",
    ):
        assert before[key] == after[key], f"{key} changed between captures"
    assert before["pages"].keys() == after["pages"].keys(), "pages changed during capture"
    if phase == "initial":  # min to max
        return
    if phase == "idle":
        assert before["navigationExpanded"] and after["navigationExpanded"]
        assert before["navigation"] == after["navigation"] and before["pages"] == after["pages"]
        assert before["zoom"] == after["zoom"], "idle changed zoom"
        return
    assert before["zoom"] == after["zoom"] and before["timestamp"] < after["timestamp"], (
        "stale interaction metadata"
    )
    if phase == "bottom":
        distance = after["scroll"]["offset"] - before["scroll"]["offset"]
        assert distance > 0.5 and abs(before["scroll"]["offset"]) <= 0.5, (
            "spread did not scroll from the top"
        )
        for page, frame in before["pages"].items():
            assert same_rect(after["pages"][page], dict(frame, top=frame["top"] - distance)), (
                "leaves did not scroll together"
            )


def verify(
    png,
    metadata,
    expected_zoom=None,
    expected_mode=None,
    after=None,
    *,
    posture=None,
    state=None,
    phase="initial",
    before=None,
    expected_page=None,
):
    data = json.loads(Path(metadata).read_text())
    assert_capture_state(data, expected_zoom, expected_mode, after, expected_page)
    # Older interactive control-check callers supply only the requested zoom.
    if posture is None:
        posture = (
            ("ipad-mini" if data["mode"] == "single" else "ipad-mini-landscape")
            if data["native"]["isIPad"]
            else "duo-folded"
            if data["native"]["closed"]
            else {
                "single": "duo-unfolded-portrait",
                "spread": "duo-unfolded-wide",
                "dualScreenBook": "duo-half-open-book",
            }[data["mode"]]
        )
    reading = check_geometry(data, posture, phase, state)
    if before is not None:
        check_pair(before, data, phase)
    image = ImageOps.exif_transpose(Image.open(png)).convert("RGB")
    dpr = data["pixelRatio"]
    assert image.size == tuple(round(data["viewport"][k] * dpr) for k in ("width", "height")), (
        "stale viewport geometry"
    )
    near_white_fraction = None
    if posture.startswith("ipad-mini") and math.isclose(data["zoom"], 1, abs_tol=0.001):
        # A permission sheet can appear after XCTest exits while the underlying
        # reader geometry remains valid. Check the final PNG itself. The seeded
        # 100% iPad pages retain >30% near-white pixels after this downsampling;
        # the observed notification sheet dims their white paper to about 204.
        sample = image.resize((128, 128), Image.Resampling.BILINEAR)
        pixels = sample.tobytes()
        near_white_fraction = sum(
            min(pixels[i:i + 3]) >= 245 for i in range(0, len(pixels), 3)
        ) / (128 * 128)
        assert near_white_fraction >= 0.20, (
            "possible obscuring overlay on final iPad screenshot: "
            f"near-white fraction {near_white_fraction:.3f} is below 0.200"
        )
    for page, frame in data["pages"].items():
        l, t, r, b = bounds(frame)
        cl, ct, cr, cb = bounds(reading)
        crop_box = tuple(
            round(v * dpr)
            for v in (
                max(l, cl, 0),
                max(t, ct, 0),
                min(r, cr, data["viewport"]["width"]),
                min(b, cb, data["viewport"]["height"]),
            )
        )
        crop = image.crop(crop_box)
        visible = Image.new("L", crop.size, 255)
        nl, nt, nr, nb = bounds(data["navigation"])
        ImageDraw.Draw(visible).rectangle(
            (
                math.floor(nl * dpr) - crop_box[0] - 2,
                math.floor(nt * dpr) - crop_box[1] - 2,
                math.ceil(nr * dpr) - crop_box[0] + 2,
                math.ceil(nb * dpr) - crop_box[1] + 2,
            ),
            fill=0,
        )
        assert visible.getbbox(), f"paper fully obscured: page {page}"
        assert sum(ImageStat.Stat(crop, visible).var) / 3 > 300, (
            f"blank or unrendered paper: page {page}"
        )
        edges = [(0, 0, 3, crop.height), (crop.width - 3, 0, crop.width, crop.height)]
        if t >= ct - 0.5:
            edges.append((0, 0, crop.width, 3))
        if b <= cb + 0.5:
            edges.append((0, crop.height - 3, crop.width, crop.height))
        for edge in edges:
            mask = visible.crop(edge)
            assert mask.getbbox(), f"paper edge fully obscured: page {page}"
            histogram = crop.crop(edge).convert("HSV").getchannel("V").histogram(mask)
            assert sum(histogram[101:]) > sum(histogram) / 2, f"missing paper edge: page {page}"
    if posture == "duo-folded":
        # The page texture alone cannot prove the dock was painted in the strip.
        box = tuple(round(v * dpr) for v in bounds(data["navigation"]))
        assert max(hi - lo for lo, hi in image.crop(box).getextrema()) > 30, "blank folded dock"
    result = {
        "verified": True,
        "zoom": data["zoom"],
        "rendered_pages": data["pages"],
        "viewport_pixels": image.size,
        "focused_page": data["focusedPage"],
    }
    if near_white_fraction is not None:
        result["near_white_fraction"] = near_white_fraction
    Path(png).with_suffix(".verification.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("png", type=Path)
    parser.add_argument("metadata", type=Path)
    parser.add_argument("--zoom", type=int)
    parser.add_argument("--mode", choices=set(MODES.values()))
    parser.add_argument("--posture", choices=MODES)
    parser.add_argument("--after", type=float)
    parser.add_argument("--page", type=int)
    args = parser.parse_args()
    print(
        json.dumps(
            verify(args.png, args.metadata, args.zoom, args.mode, args.after, posture=args.posture,
                   expected_page=args.page),
            indent=2,
        )
    )
