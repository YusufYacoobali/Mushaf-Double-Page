#!/usr/bin/env python3
"""Verify native Android emulator frames against measured folding features.

This deliberately keeps Android's system insets. The separate iOS verifier owns
Duo's bottom-swipe extension; an Android capture must not inherit that exception.
"""

from datetime import datetime
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps, ImageStat

from verify_fitted_capture import bounds, rect, same_rect


POSTURES = {
    "folded": "single",
    "unfolded-portrait": "single",
    "unfolded-landscape": "spread",
    "half-open-book": "dualScreenBook",
}
PROFILES = {"galaxy-z-fold8", "galaxy-z-fold8-ultra"}
EMULATION = "samsung-dimensions-stock-android"
PACKAGE = "com.quran.quran_double_page"
TOLERANCE = 0.5


def close(actual, expected, message):
    assert math.isfinite(actual) and math.isclose(actual, expected, abs_tol=TOLERANCE), message


def timestamp(value):
    stamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
    assert stamp.tzinfo is not None, "geometry timestamp has no timezone"
    return stamp.timestamp()


def assert_capture_state(data, expected_zoom=None, posture=None, after=None, expected_page=6):
    assert data["mode"] in POSTURES.values(), "unknown Android reading mode"
    if posture is not None:
        assert posture in POSTURES, "unknown requested Android posture"
        assert data["mode"] == POSTURES[posture], "wrong Android reading mode"
    if expected_zoom is not None:
        assert math.isclose(data["zoom"] * 100, expected_zoom, abs_tol=0.1), "wrong actual rendered zoom"
    assert 0 < data["zoom"] <= 1, "invalid rendered zoom"
    stamp = timestamp(data["timestamp"])
    if after is not None:
        assert stamp >= after, "stale rendered geometry timestamp"
    wanted = {str(expected_page)}
    if data["mode"] != "single":
        wanted.add(str(expected_page + 1))
    assert data["focusedPage"] == expected_page and set(data["pages"]) == wanted, (
        "wrong requested Quran pages"
    )
    assert data.get("edition") in {"indopak_tajweed", "madani"}, "unknown Mushaf aspect ratio"
    assert data.get("safeRegions"), "missing Android safe display regions"
    assert not data["native"]["isIPad"], "iPad frame supplied to Android verifier"
    assert not data["native"]["divisions"], "iOS division geometry cannot prove Android folding"
    for key in ("width", "height"):
        assert math.isfinite(data["viewport"][key]) and data["viewport"][key] > 0, "invalid viewport"
    assert math.isfinite(data["pixelRatio"]) and data["pixelRatio"] > 0, "invalid pixel ratio"
    for frame in data["pages"].values():
        assert all(math.isfinite(frame[k]) for k in ("left", "top", "width", "height")), (
            "nonfinite page geometry"
        )
        assert frame["width"] > 0 and frame["height"] > 0, "empty rendered page"


def android_panels(data):
    """Reconstruct safe regions from raw Android padding and physical dividers."""
    w, h = (data["viewport"][k] for k in ("width", "height"))
    pad = data["padding"]
    for source in (pad, data["viewPadding"]):
        assert all(math.isfinite(source[k]) and source[k] >= 0
                   for k in ("left", "top", "right", "bottom")), "invalid Android system insets"
    assert pad["left"] + pad["right"] < w and pad["top"] + pad["bottom"] < h
    panels = [(pad["left"], pad["top"], w - pad["right"], h - pad["bottom"])]
    for feature in data["frameworkFeatures"]:
        frame = feature["bounds"]
        assert all(math.isfinite(frame[k]) for k in ("left", "top", "width", "height")), (
            "nonfinite framework feature"
        )
        assert frame["width"] >= 0 and frame["height"] >= 0, "invalid framework feature dimensions"
        separating = feature["type"] in ("hinge", "cutout") or (
            feature["type"] == "fold" and feature["state"] == "postureHalfOpened"
        )
        if not separating:
            continue
        x, y, xx, yy = bounds(frame)
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
    actual = sorted(data["safeRegions"], key=bounds)
    assert len(actual) == len(expected) and all(same_rect(a, b) for a, b in zip(actual, expected)), (
        "safe regions disagree with raw Android geometry"
    )
    return expected


def check_profile(data, state):
    """Tie the native frame to the exact published custom-AVD declaration."""
    profile = state.get("profileMetadata")
    assert isinstance(profile, dict) and profile.get("schemaVersion") == 1, "missing Samsung profile metadata"
    assert profile.get("profileId") == state["profile"], "profile declaration belongs to another device"
    emulation = profile.get("emulation", {})
    assert (emulation.get("kind") == EMULATION and emulation.get("os") == "stock-android"
            and emulation.get("oneUi") is False and emulation.get("realSamsungDevice") is False), (
        "profile must disclose stock Android layout emulation, not Samsung firmware"
    )
    assert profile.get("sources") and profile.get("assumptions"), "missing profile sources or emulation assumptions"
    screen = "cover" if state["requestedPosture"] == "folded" else "inner"
    display = profile["displays"][screen]
    for key in ("width", "height", "densityDpi"):
        assert isinstance(display[key], (int, float)) and display[key] > 0, "invalid Samsung display specification"
    pixels = [round(data["viewport"][k] * data["pixelRatio"]) for k in ("width", "height")]
    assert sorted(pixels) == sorted([display["width"], display["height"]]), (
        "actual native viewport does not match the declared Samsung display pixels"
    )
    close(data["pixelRatio"] * 160, display["densityDpi"], "actual Android density differs from declared emulation density")
    if screen == "inner":
        folds = [f for f in data["frameworkFeatures"] if f["type"] in ("fold", "hinge")]
        assert len(folds) == 1, "expected exactly one actual folding feature"
        feature = folds[0]["bounds"]
        w, h = (data["viewport"][k] for k in ("width", "height"))
        natural = profile["displays"]["inner"]
        vertical = pixels == [natural["width"], natural["height"]]
        expected = rect(w / 2, 0, 0, h) if vertical else rect(0, h / 2, w, 0)
        assert same_rect(feature, expected), "actual framework fold differs from the declared physical hinge"
    return display


def check_posture(data, posture, state=None):
    assert posture in POSTURES and data["mode"] == POSTURES[posture], "wrong Android reading mode"
    w, h = (data["viewport"][k] for k in ("width", "height"))
    folds = [f for f in data["frameworkFeatures"] if f["type"] in ("fold", "hinge")]
    if posture == "folded":
        assert h > w, "folded cover must be portrait"
        assert not folds, "closed cover still reports an inner-display fold"
        assert not data["fit"], "closed Android cover must retain ordinary-phone sizing"
    elif posture == "half-open-book":
        assert data["fit"], "book must use foldable fitting"
        assert any(f["state"] == "postureHalfOpened" and
                   f["bounds"]["height"] > f["bounds"]["width"] for f in folds), (
            "missing actual vertical half-open Android fold"
        )
    else:
        assert folds and all(f["state"] == "postureFlat" for f in folds), (
            "missing actual flat Android fold"
        )
        assert data["fit"], "unfolded Android frame must use foldable sizing"
        assert (h > w) == (posture == "unfolded-portrait"), "wrong unfolded orientation"
    if state is None:
        return
    assert state["profile"] in PROFILES, "unknown Samsung AVD profile"
    assert state.get("emulation") == EMULATION, "capture must disclose Samsung dimensions on stock Android"
    assert state.get("emulatorPostureSource") == "hinge-angle0", "missing actual emulator hinge sensor source"
    assert state["requestedPosture"] == posture, "native state belongs to another posture"
    check_profile(data, state)
    expected = 1 if posture == "folded" else 2 if posture == "half-open-book" else 3
    assert state["emulatorPosture"] == expected, "native emulator posture disagrees with requested posture"
    assert isinstance(state.get("deviceState"), str) and state["deviceState"].strip(), (
        "missing actual Android device-state evidence"
    )
    for key in ("displayDump", "windowDump"):
        assert isinstance(state.get(key), str) and state[key].strip(), f"missing native {key}"
    assert state["foregroundPackage"] == PACKAGE, "reader is not the actual foreground Android app"
    assert state["noSystemDialogs"] is True, "Android system dialog obscures the capture"
    captured = state["deviceTimestamp"]
    assert isinstance(captured, (int, float)) and math.isfinite(captured), "invalid native capture clock"
    age = captured - timestamp(data["timestamp"])
    assert -2 <= age <= 120, "geometry is stale relative to the Android screenshot clock"
    angle = state.get("hingeAngle")
    assert isinstance(angle, (int, float)) and math.isfinite(angle), "missing actual native hinge angle"
    assert (0 <= angle <= 15 if expected == 1 else
            45 <= angle <= 135 if expected == 2 else 160 <= angle <= 180), (
        "native hinge angle disagrees with requested posture"
    )


def check_geometry(data, posture, phase="initial", state=None):
    check_posture(data, posture, state)
    assert phase in ("initial", "collapsed", "bottom"), "unknown capture phase"
    panels = android_panels(data)
    w, h = (data["viewport"][k] for k in ("width", "height"))
    mode, z = data["mode"], data["zoom"]
    aspect = 2096 / 3008 if data["edition"] == "madani" else 721 / 1058
    pages = sorted(data["pages"].items(), key=lambda item: item[1]["left"])
    expected_sizing = {"single": "portraitHeight", "spread": "spreadWidth", "dualScreenBook": "regionFit"}
    assert data["sizing"] == expected_sizing[mode], "wrong Android page sizing"
    expanded = data["navigationExpanded"]
    assert isinstance(expanded, bool), "missing settled navigation state"
    label = "Collapse navigation" if expanded else "Open navigation"
    assert label in data["controls"], "missing actual navigation tab"
    tab = data["controls"][label]
    assert data["navigation"] and tab["width"] > 0 and tab["height"] > 0
    if not expanded:
        assert same_rect(data["navigation"], tab), "collapsed footprint differs from tab"
    if mode == "single":
        assert len(panels) == 1, "portrait must use one continuous Android panel"
        safe = panels[0]
        reading = rect(0, 0, w, h) if posture == "folded" else rect(safe["left"], 0, safe["width"], h)
        regions = [reading]
        expected = [dict(reading, top=h * (1 - z) / 2, height=h * z)]
        assert data["scroll"] is None, "portrait unexpectedly has a spread scroll"
        if phase == "collapsed":
            assert not expanded, "navigation must be collapsed"
        if not expanded:
            close(bounds(tab)[3], h - max(8, data["padding"]["bottom"]), "wrong Android collapsed tab bottom")
            close(tab["left"] + tab["width"] / 2,
                  reading["left"] + reading["width"] / 2, "collapsed tab is off centre")
    else:
        assert len(pages) == 2 and int(pages[0][0]) == int(pages[1][0]) + 1, "wrong RTL page order"
        if mode == "spread":
            assert len(panels) == 1, "flat Android spread must be continuous"
            reading = panels[0]
            half = (reading["width"] - 1) / 2
            regions = [dict(reading, width=half),
                       dict(reading, left=reading["left"] + half + 1, width=half)]
            width, height = half * z, half * z / aspect
            scroll = data["scroll"]
            assert scroll and scroll["settled"] and same_rect(scroll["viewport"], reading), (
                "missing settled Android scroll viewport"
            )
            overflow = max(0, height - reading["height"])
            close(scroll["min"], 0, "incorrect minimum scroll extent")
            close(scroll["max"], overflow, "incorrect maximum scroll extent")
            offset = overflow if phase == "bottom" else 0
            close(scroll["offset"], offset, "wrong scroll endpoint")
            x = reading["left"] + half - width
            expected = [rect(x, reading["top"] - offset, width, height),
                        rect(x + width + 1, reading["top"] - offset, width, height)]
        else:
            assert len(panels) == 2, "book requires two physical Android panels"
            left, right = panels
            close(left["top"], right["top"], "book panels have different top edges")
            close(left["height"], right["height"], "book panels have different heights")
            assert bounds(left)[2] <= right["left"] + TOLERANCE, "book panels cross the hinge"
            assert int(pages[1][0]) == data["focusedPage"], "focused book page is not on the right"
            regions = panels
            reading = dict(left, width=bounds(right)[2] - left["left"])
            width = min(min(p["width"], p["height"] * aspect) for p in panels) * z
            height = width / aspect
            expected = [rect(p["left"] + (p["width"] - width) / 2,
                             p["top"] + (p["height"] - height) / 2, width, height) for p in panels]
            assert data["scroll"] is None, "book should fit complete pages without a shared scroll"
    assert same_rect(data["readingBounds"], reading), "incorrect Android reading bounds"
    assert len(data["regions"]) == len(regions) and all(
        same_rect(a, b) for a, b in zip(data["regions"], regions)
    ), "incorrect Android page regions"
    for (page, actual), target in zip(pages, expected):
        assert same_rect(actual, target), f"page {page} bounds {actual} differ from {target}"
    # All actual tab/control bounds must remain inside one unobstructed safe
    # panel. Portrait tabs have their own Android system-navigation clearance.
    control_panel = panels[-1] if len(panels) == 2 else panels[0]
    nl, nt, nr, nb = bounds(data["navigation"])
    cl, ct, cr, cb = bounds(control_panel)
    assert nl >= cl - TOLERANCE and nr <= cr + TOLERANCE, "navigation crosses a physical panel edge"
    assert nt >= ct - TOLERANCE and nb <= cb + TOLERANCE, "navigation overlaps Android system insets"
    if mode == "dualScreenBook":
        for frame in data["pages"].values():
            l, t, r, b = bounds(frame)
            assert any(l >= pl - TOLERANCE and t >= pt - TOLERANCE and
                       r <= pr + TOLERANCE and b <= pb + TOLERANCE
                       for pl, pt, pr, pb in map(bounds, panels)), "page crosses the physical fold"
    return reading


def check_pair(before, after, phase):
    for key in ("viewport", "pixelRatio", "edition", "safeRegions", "readingBounds", "sizing", "focusedPage"):
        assert before[key] == after[key], f"{key} changed between captures"
    assert before["pages"].keys() == after["pages"].keys(), "pages changed during capture"
    assert timestamp(before["timestamp"]) < timestamp(after["timestamp"]), "stale interaction metadata"
    if phase == "initial":
        assert before["zoom"] < after["zoom"], "min/max pair did not increase zoom"
        return
    assert before["zoom"] == after["zoom"], "interaction changed zoom"
    if phase == "collapsed":
        assert before["navigationExpanded"] and not after["navigationExpanded"], "collapse transition missing"
        assert before["pages"] == after["pages"], "collapse moved paper"
    elif phase == "bottom":
        maximum = after["scroll"]["max"]
        distance = after["scroll"]["offset"] - before["scroll"]["offset"]
        close(before["scroll"]["offset"], 0, "spread did not start at its top")
        close(distance, maximum, "spread did not reach its bottom")
        # Near-square inner displays can fit both full-width pages completely.
        # Zero movement is correct only when the measured scroll range is zero.
        assert maximum <= TOLERANCE or distance > TOLERANCE, "scroll did not move"
        for page, frame in before["pages"].items():
            assert same_rect(after["pages"][page], dict(frame, top=frame["top"] - distance)), (
                "leaves did not scroll together"
            )


def check_pixels(image, data, reading, phase):
    dpr = data["pixelRatio"]
    for page, frame in data["pages"].items():
        l, t, r, b = bounds(frame)
        cl, ct, cr, cb = bounds(reading)
        crop_box = tuple(round(v * dpr) for v in
                         (max(l, cl, 0), max(t, ct, 0),
                          min(r, cr, data["viewport"]["width"]), min(b, cb, data["viewport"]["height"])))
        assert crop_box[2] > crop_box[0] and crop_box[3] > crop_box[1], "paper is outside actual PNG"
        crop = image.crop(crop_box)
        visible = Image.new("L", crop.size, 255)
        nl, nt, nr, nb = bounds(data["navigation"])
        ImageDraw.Draw(visible).rectangle((math.floor(nl * dpr) - crop_box[0] - 2,
                                          math.floor(nt * dpr) - crop_box[1] - 2,
                                          math.ceil(nr * dpr) - crop_box[0] + 2,
                                          math.ceil(nb * dpr) - crop_box[1] + 2), fill=0)
        assert visible.getbbox(), f"paper fully obscured: page {page}"
        assert sum(ImageStat.Stat(crop, visible).var) / 3 > 300, f"blank or unrendered paper: page {page}"
        edges = [(0, 0, min(3, crop.width), crop.height), (max(0, crop.width - 3), 0, crop.width, crop.height)]
        if t >= ct - TOLERANCE:
            edges.append((0, 0, crop.width, min(3, crop.height)))
        if b <= cb + TOLERANCE:
            edges.append((0, max(0, crop.height - 3), crop.width, crop.height))
        for edge in edges:
            mask = visible.crop(edge)
            assert mask.getbbox(), f"paper edge fully obscured: page {page}"
            histogram = crop.crop(edge).convert("HSV").getchannel("V").histogram(mask)
            assert sum(histogram[101:]) > sum(histogram) / 2, f"missing paper edge: page {page}"
    if phase == "collapsed":
        tab = data["controls"]["Open navigation"]
        close(tab["width"], 72, "incorrect collapsed arrow width")
        close(tab["height"], 24, "incorrect collapsed arrow height")
        x, y = tab["left"] + tab["width"] / 2, tab["top"] + tab["height"] / 2
        glyph = image.crop(tuple(round(v * dpr) for v in (x - 6, y - 4, x + 6, y + 4)))
        assert max(high - low for low, high in glyph.getextrema()) > 30, "missing visible navigation arrow"


def verify(png, metadata, expected_zoom, posture, *, state, phase="initial", before=None,
           expected_page=6, after=None, profile=None):
    data = json.loads(Path(metadata).read_text())
    if isinstance(state, (str, Path)):
        state = json.loads(Path(state).read_text())
    if isinstance(before, (str, Path)):
        before = json.loads(Path(before).read_text())
    assert state is not None, "missing native Android state evidence"
    if profile is not None:
        assert state["profile"] == profile, "wrong AVD profile"
    assert_capture_state(data, expected_zoom, posture, after, expected_page)
    reading = check_geometry(data, posture, phase, state)
    if before is not None:
        check_pair(before, data, phase)
    image = ImageOps.exif_transpose(Image.open(png)).convert("RGB")
    wanted = tuple(round(data["viewport"][k] * data["pixelRatio"]) for k in ("width", "height"))
    assert image.size == wanted and list(image.size) == state["pixelSize"], "stale physical display or viewport geometry"
    check_pixels(image, data, reading, phase)
    result = {
        "verified": True,
        "platform": "android",
        "emulation": EMULATION,
        "profile": state["profile"],
        "posture": posture,
        "phase": phase,
        "zoom": data["zoom"],
        "focused_page": data["focusedPage"],
        "rendered_pages": data["pages"],
        "viewport_pixels": image.size,
        "native_posture": state["emulatorPosture"],
        "native_posture_source": state["emulatorPostureSource"],
        "hinge_angle": state["hingeAngle"],
        "android_system_insets": data["padding"],
        "reading_bottom_inset": data["viewport"]["height"] - bounds(reading)[3],
        "scroll_range": data["scroll"]["max"] if data["scroll"] else None,
        "page_bottom_margins": {p: bounds(reading)[3] - bounds(frame)[3] for p, frame in data["pages"].items()},
        "system_dialog_free": True,
        "display_emulation": state["profileMetadata"]["displays"]["cover" if posture == "folded" else "inner"],
        "one_ui_verified": False,
        "real_samsung_device_verified": False,
    }
    Path(png).with_suffix(".verification.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("png", type=Path)
    parser.add_argument("metadata", type=Path)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--posture", required=True, choices=POSTURES)
    parser.add_argument("--profile", choices=sorted(PROFILES))
    parser.add_argument("--zoom", required=True, type=int)
    parser.add_argument("--phase", choices=("initial", "collapsed", "bottom"), default="initial")
    parser.add_argument("--before", type=Path)
    parser.add_argument("--page", type=int, default=6)
    parser.add_argument("--after", type=float)
    args = parser.parse_args()
    print(json.dumps(verify(args.png, args.metadata, args.zoom, args.posture, state=args.state,
                            phase=args.phase, before=args.before, expected_page=args.page,
                            after=args.after, profile=args.profile), indent=2))
