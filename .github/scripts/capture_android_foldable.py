#!/usr/bin/env python3
"""Capture genuine Android foldable frames; never inject reader geometry.

The Samsung profiles emulate declared display dimensions on stock Android.
They are not Samsung hardware or One UI. Every screenshot records that scope.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import io
import json
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

from PIL import Image

from verify_android_foldable_capture import assert_capture_state, verify


PACKAGE = "com.quran.quran_double_page"
ACTIVITY = PACKAGE + "/.MainActivity"
GEOMETRY = "app_flutter/reader-geometry.json"
PREFERENCES = "shared_prefs/FlutterSharedPreferences.xml"
DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"
PROFILES = ("galaxy-z-fold8", "galaxy-z-fold8-ultra")
POSTURES = ("folded", "unfolded-portrait", "unfolded-landscape", "half-open-book")
TURN_POSTURES = ("folded", "unfolded-landscape")


def turn_swipe(frame, forward):
    """Drag across the outgoing sheet, inside the visible reading viewport."""
    leaves = sorted(frame["pages"].values(), key=lambda rect: rect["left"])
    leaf = leaves[0 if forward else -1]
    bounds = frame["readingBounds"]
    left, top = max(bounds["left"], leaf["left"]), max(bounds["top"], leaf["top"])
    right = min(bounds["left"] + bounds["width"], leaf["left"] + leaf["width"])
    bottom = min(bounds["top"] + bounds["height"], leaf["top"] + leaf["height"])
    assert right > left and bottom > top, "No visible outgoing page"
    start, end = left + .12 * (right - left), right - .12 * (right - left)
    y = (top + bottom) / 2
    if not forward:
        start, end = end, start
    return [round(v * frame["pixelRatio"]) for v in (start, y, end, y)]


def write_json(path, data):
    Path(path).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")


def timestamp(frame):
    return datetime.fromisoformat(frame["timestamp"].replace("Z", "+00:00")).timestamp()


def hinge_angle(output):
    """Read the actual console sensor, rather than the posture command sent."""
    match = re.search(r"hinge-angle0\s*[:=]\s*([-+]?\d+(?:\.\d+)?)", output)
    if not match:
        raise AssertionError("No actual hinge-angle0 value in emulator response: " + output)
    value = float(match.group(1))
    assert math.isfinite(value) and 0 <= value <= 180, "Invalid actual hinge angle"
    return value


def actual_posture(angle):
    if angle <= 5:
        return 1
    if 60 <= angle <= 120:
        return 2
    if angle >= 175:
        return 3
    raise AssertionError(f"Hinge has not reached a requested endpoint: {angle}")


def foreground_window(windows):
    # Android 16 prints per-display focus in DISPLAY CONTENTS, which is absent
    # from `dumpsys window windows`. Read the full dump and join it to the
    # current top-focused display; ignore historical LAST ANR sections.
    section, display = None, None
    top_displays, focuses = [], {}
    for line in windows.splitlines():
        if line.startswith("WINDOW MANAGER "):
            section = ("displays" if line.startswith("WINDOW MANAGER DISPLAY CONTENTS ")
                       else "windows" if line.startswith("WINDOW MANAGER WINDOWS ") else None)
            display = None
        if section == "windows":
            match = re.fullmatch(r"\s*mTopFocusedDisplayId=(\d+)\s*", line)
            if match:
                top_displays.append(int(match.group(1)))
        elif section == "displays":
            match = re.match(r"\s*Display: mDisplayId=(\d+)\b", line)
            if match:
                display = int(match.group(1))
            match = re.match(r"\s*mCurrentFocus=(.*)$", line)
            if match:
                assert display is not None, "Window focus has no associated display"
                assert display not in focuses, "Ambiguous window focus for one display"
                focuses[display] = match.group(1)
    assert len(top_displays) == 1, "No unambiguous top-focused Android display"
    display = top_displays[0]
    assert display in focuses, "No current window focus for the top-focused display"
    # A permission sheet can be focused while the app remains resumed. Never
    # substitute mFocusedApp, visible activities or focus on another display.
    match = re.fullmatch(r"Window\{\S+\s+u\d+\s+([A-Za-z0-9_.]+)/[^}]+\}", focuses[display])
    assert match, "No foreground activity in the top-focused Android window"
    return {"displayId": display, "package": match.group(1)}


def foreground_package(windows):
    return foreground_window(windows)["package"]


def unobstructed_ui(xml):
    root = ET.fromstring(xml)
    forbidden = {
        "com.android.permissioncontroller", "com.google.android.permissioncontroller",
        "com.android.packageinstaller", "com.google.android.packageinstaller",
    }
    nodes = list(root.iter("node"))
    assert nodes, "Empty native UI hierarchy"
    assert any(node.get("package") == PACKAGE for node in nodes), "Reader absent from native UI"
    for node in nodes:
        assert node.get("package") not in forbidden, "System permission sheet covers reader"
        assert node.get("resource-id") != "android:id/alertTitle", "Native alert covers reader"
    return True


def preference_xml(existing, page):
    root = ET.fromstring(existing) if existing.strip() else ET.Element("map")
    assert root.tag == "map", "Unexpected SharedPreferences format"
    replacements = {
        "flutter.CurrentPage1": ("long", str(page)),
        "flutter.quran_single_page_scale": ("string", DOUBLE_PREFIX + "0.7"),
        "flutter.quran_landscape_page_scale": ("string", DOUBLE_PREFIX + "0.6"),
        "flutter.reader_controls_arrow_only": ("boolean", "false"),
        "flutter.review_prompt_rate_chosen": ("boolean", "true"),
    }
    for child in list(root):
        if child.get("name") in replacements:
            root.remove(child)
    for name, (kind, value) in replacements.items():
        element = ET.SubElement(root, kind, {"name": name})
        if kind == "string":
            element.text = value
        else:
            element.set("value", value)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


class Capture:
    def __init__(self, serial, profile, metadata, output, page):
        self.serial, self.profile, self.metadata = serial, profile, metadata
        self.output, self.page = Path(output), page
        self.output.mkdir(parents=True, exist_ok=True)
        self.rotation = None
        self.supported_states = ""
        self.failures = []
        self.completed = []

    def adb(self, *args, timeout=30, check=True, binary=False):
        result = subprocess.run(
            ["adb", "-s", self.serial, *map(str, args)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout,
        )
        if check and result.returncode:
            raise RuntimeError(f"adb {' '.join(map(str, args[:4]))}: " + result.stderr.decode(errors="replace"))
        return result.stdout if binary else result.stdout.decode(errors="replace").strip()

    def shell(self, *args, **kwargs):
        return self.adb("shell", shlex.join([str(a) for a in args]), **kwargs)

    def run_as(self, *args, **kwargs):
        return self.adb("exec-out", shlex.join(["run-as", PACKAGE, *map(str, args)]), **kwargs)

    def device_clock(self):
        value = self.shell("date", "+%s.%N")
        try:
            return float(value)
        except ValueError:
            raise RuntimeError("Device clock must provide a numeric subsecond timestamp: " + value)

    def frame(self):
        return json.loads(self.run_as("cat", GEOMETRY))

    def wait_frame(self, predicate=lambda frame: True, after=None, timeout=35, expected_page=None):
        deadline = time.monotonic() + timeout
        error, previous = "No reader geometry", None
        while time.monotonic() < deadline:
            try:
                frame = self.frame()
                observed_mode = {
                    "single": "folded", "spread": "unfolded-landscape",
                    "dualScreenBook": "half-open-book",
                }[frame["mode"]]
                assert_capture_state(frame, posture=observed_mode, after=after,
                                     expected_page=self.page if expected_page is None else expected_page)
                assert predicate(frame), "Reader has not reached requested state"
                assert frame.get("scroll") is None or frame["scroll"]["settled"], "Reader scroll is moving"
                if frame == previous:
                    return frame
                previous = frame
            except (ValueError, KeyError, TypeError, AssertionError, RuntimeError) as exc:
                error = str(exc)
                previous = None
            time.sleep(0.25)
        raise RuntimeError("Timed out waiting for settled reader: " + error)

    def prepare(self):
        assert self.metadata["profileId"] == self.profile
        scope = self.metadata["emulation"]
        assert scope["kind"] == "samsung-dimensions-stock-android"
        assert scope["oneUi"] is False and scope["realSamsungDevice"] is False
        self.shell("am", "force-stop", PACKAGE)
        existing = self.run_as("cat", PREFERENCES, check=False)
        if not existing.lstrip().startswith("<?xml") and not existing.lstrip().startswith("<map"):
            existing = ""
        local = self.output / "seed-preferences.xml"
        local.write_bytes(preference_xml(existing, self.page))
        remote = "/data/local/tmp/reader-qa-preferences.xml"
        self.adb("push", str(local), remote)
        self.shell("chmod", "644", remote)
        self.run_as("mkdir", "-p", "shared_prefs")
        self.run_as("cp", remote, PREFERENCES)
        self.run_as("rm", "-f", GEOMETRY)
        # This permission is configured only on the disposable QA emulator.
        self.shell("pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
        self.shell("settings", "put", "system", "accelerometer_rotation", "0")
        self.shell("settings", "put", "system", "screen_off_timeout", "1800000")
        self.shell("svc", "power", "stayon", "true")
        self.shell("input", "keyevent", "KEYCODE_WAKEUP")
        self.shell("wm", "dismiss-keyguard")
        self.supported_states = self.shell("cmd", "device_state", "print-states")
        (self.output / "supported-device-states.txt").write_text(self.supported_states + "\n")
        started = self.device_clock()
        self.shell("am", "start", "-W", "-n", ACTIVITY, timeout=90)
        deadline = time.monotonic() + 300
        error = "Quran assets not available"
        while time.monotonic() < deadline:
            files = self.run_as("find", "app_flutter/indopak_tajweed", "-type", "f", "-name", "*.webp", check=False)
            count = sum(line.endswith(".webp") for line in files.splitlines())
            if count >= 851:
                self.wait_frame(after=started, timeout=45)
                print(f"{self.profile}: loaded {count} genuine Quran pages", flush=True)
                return
            error = f"{count}/851 Quran images"
            time.sleep(3)
        raise RuntimeError("Reader startup failed: " + error)

    def tap(self, rectangle, frame):
        x = (rectangle["left"] + rectangle["width"] / 2) * frame["pixelRatio"]
        y = (rectangle["top"] + rectangle["height"] / 2) * frame["pixelRatio"]
        assert 0 <= x < frame["viewport"]["width"] * frame["pixelRatio"]
        assert 0 <= y < frame["viewport"]["height"] * frame["pixelRatio"]
        self.shell("input", "tap", str(round(x)), str(round(y)))

    def dock(self, expanded, refresh=False):
        frame = self.wait_frame()
        if refresh and expanded and frame["navigationExpanded"]:
            before = self.device_clock()
            self.tap(frame["controls"]["Collapse navigation"], frame)
            frame = self.wait_frame(lambda f: f["navigationExpanded"] is False, after=before)
        if frame["navigationExpanded"] != expanded:
            before = self.device_clock()
            self.tap(frame["controls"]["Open navigation" if expanded else "Collapse navigation"], frame)
            frame = self.wait_frame(lambda f: f["navigationExpanded"] == expanded, after=before)
        return frame

    def zoom(self, target):
        for step in range(24):
            frame = self.wait_frame()
            if abs(frame["zoom"] * 100 - target) < 0.1:
                return frame
            frame = self.dock(True, refresh=step % 3 == 0)
            current = frame["zoom"]
            action = "Zoom in" if current * 100 < target else "Zoom out"
            before = self.device_clock()
            self.tap(frame["controls"][action], frame)
            self.wait_frame(lambda f: abs(f["zoom"] - current) > 0.001, after=before, timeout=12)
        raise RuntimeError(f"Actual zoom controls did not reach {target}%")

    @staticmethod
    def matches_orientation(frame, posture):
        width, height = frame["viewport"]["width"], frame["viewport"]["height"]
        if posture == "half-open-book":
            return any(
                feature["type"] in ("fold", "hinge")
                and feature["state"] == "postureHalfOpened"
                and feature["bounds"]["height"] > feature["bounds"]["width"]
                for feature in frame["frameworkFeatures"]
            )
        return width < height if posture in ("folded", "unfolded-portrait") else width > height

    def posture(self, posture):
        started = self.device_clock()
        if posture == "folded":
            self.adb("emu", "fold")
        else:
            self.adb("emu", "unfold")
            if posture == "half-open-book":
                self.adb("emu", "posture", "2")
        expected = 1 if posture == "folded" else 2 if posture == "half-open-book" else 3
        for _ in range(40):
            observed = hinge_angle(self.adb("emu", "sensor", "get", "hinge-angle0"))
            try:
                if actual_posture(observed) == expected:
                    break
            except AssertionError:
                pass
            time.sleep(0.25)
        else:
            raise RuntimeError(f"Native hinge did not reach {posture}: {observed}")
        self.shell("input", "keyevent", "KEYCODE_WAKEUP")
        self.shell("wm", "dismiss-keyguard")
        self.shell("am", "start", "-W", "-n", ACTIVITY, timeout=60)
        errors = []
        for rotation in range(4):
            self.shell("cmd", "window", "user-rotation", "-d", "0", "lock", str(rotation))
            self.rotation = rotation
            try:
                frame = self.wait_frame(
                    lambda f: self.matches_orientation(f, posture), after=started, timeout=12,
                )
                expected_mode = "dualScreenBook" if posture == "half-open-book" else "spread" if posture == "unfolded-landscape" else "single"
                assert frame["mode"] == expected_mode, f"Wrong native reader mode: {frame['mode']}"
                return started
            except (AssertionError, RuntimeError) as exc:
                errors.append(f"rotation {rotation}: {exc}")
        raise RuntimeError(f"No real {posture} orientation: " + "; ".join(errors))

    def ui_state(self, name, posture):
        remote = "/sdcard/reader-qa-window.xml"
        self.shell("rm", "-f", remote)
        self.shell("uiautomator", "dump", "--compressed", remote, timeout=35)
        xml = self.shell("cat", remote)
        (self.output / (name + ".ui.xml")).write_text(xml + "\n")
        unobstructed_ui(xml)
        windows = self.shell("dumpsys", "window")
        focus = foreground_window(windows)
        foreground = focus["package"]
        assert foreground == PACKAGE, "Reader is not the focused Android window: " + foreground
        angle_text = self.adb("emu", "sensor", "get", "hinge-angle0")
        angle = hinge_angle(angle_text)
        return {
            "profile": self.profile, "requestedPosture": posture,
            "emulation": "samsung-dimensions-stock-android", "profileMetadata": self.metadata,
            "deviceState": self.shell("cmd", "device_state", "state"),
            "supportedDeviceStates": self.supported_states,
            "emulatorPosture": actual_posture(angle), "emulatorPostureSource": "hinge-angle0",
            "hingeAngle": angle, "hingeSensor": angle_text,
            "foregroundPackage": foreground, "noSystemDialogs": True,
            "focusedDisplayId": focus["displayId"],
            "displayDump": self.shell("dumpsys", "display"), "windowDump": windows,
            "userRotation": self.rotation, "uiDumpFile": name + ".ui.xml",
        }

    def screenshot(self, frame):
        expected = tuple(round(frame["viewport"][key] * frame["pixelRatio"]) for key in ("width", "height"))
        display_ids = self.shell("dumpsys", "SurfaceFlinger", "--display-id")
        ids = list(dict.fromkeys(re.findall(r"\bDisplay\s+(\d+)", display_ids)))
        # A single-display AVD may not expose --display-id. The default remains
        # acceptable only when its real PNG exactly matches the active viewport.
        candidates = ids if ids else [None]
        failures = []
        for display_id in candidates:
            args = ["screencap", "-p"]
            if display_id is not None:
                args.extend(["-d", display_id])
            raw = self.adb("exec-out", shlex.join(args), binary=True, timeout=30)
            try:
                with Image.open(io.BytesIO(raw)) as png:
                    assert png.format == "PNG"
                    if png.size == expected:
                        return raw, display_id, display_ids
                    failures.append(f"display {display_id}: {png.size}")
            except (OSError, AssertionError) as exc:
                failures.append(f"display {display_id}: {exc}")
        raise AssertionError(f"No physical display PNG matches active reader {expected}: " + "; ".join(failures))

    def capture(self, name, posture, percent, after, phase="initial", before=None, expanded=None):
        deadline = time.monotonic() + 70
        last_error = "No matching capture"
        png = self.output / (name + ".png")
        layout = png.with_suffix(".layout.json")
        while time.monotonic() < deadline:
            try:
                state = self.ui_state(name, posture)
                if expanded is not None:
                    self.dock(expanded, refresh=expanded)
                frame = self.wait_frame(
                    lambda f: abs(f["zoom"] * 100 - percent) < 0.1
                    and self.matches_orientation(f, posture)
                    and (expanded is None or f["navigationExpanded"] is expanded),
                    after=after, timeout=15,
                )
                state["deviceTimestamp"] = self.device_clock()
                raw, display_id, display_ids = self.screenshot(frame)
                following = self.frame()
                time.sleep(0.35)
                assert following == frame == self.frame(), "Reader changed during screenshot"
                assert foreground_window(self.shell("dumpsys", "window")) == {
                    "displayId": state["focusedDisplayId"], "package": PACKAGE,
                }, "Window focus changed during screenshot"
                state["pixelSize"] = list(Image.open(io.BytesIO(raw)).size)
                state["physicalDisplayId"] = display_id
                state["surfaceFlingerDisplays"] = display_ids
                png.write_bytes(raw)
                write_json(layout, frame)
                write_json(self.output / (name + "-state.json"), state)
                verify(
                    png, layout, percent, posture, state=state, phase=phase,
                    before=before, expected_page=self.page, after=after,
                )
                self.completed.append(name)
                print(json.dumps({"capture": name, "verified": True, "zoom": frame["zoom"], "viewport": frame["viewport"], "pages": frame["pages"], "scroll": frame["scroll"]}), flush=True)
                return frame
            except (OSError, ValueError, KeyError, TypeError, AssertionError, RuntimeError, subprocess.TimeoutExpired) as exc:
                last_error = str(exc)
                time.sleep(0.4)
        raise RuntimeError(name + ": " + last_error)

    def bottom(self):
        # Renew the real dock state before collapsing it. This guarantees a
        # fresh measured frame even when width-fit pages have no overflow and
        # the subsequent swipe legitimately leaves the scroll offset at zero.
        self.dock(True)
        frame = self.dock(False)
        scroll = frame["scroll"]
        assert scroll and scroll["settled"], "Missing landscape scroll viewport"
        viewport = scroll["viewport"]
        page = frame["pages"][str(self.page)]
        dpr = frame["pixelRatio"]
        x = (page["left"] + page["width"] * 0.35) * dpr
        start = (viewport["top"] + viewport["height"] * 0.75) * dpr
        end = (viewport["top"] + viewport["height"] * 0.2) * dpr
        before = self.device_clock()
        for _ in range(4):
            self.shell("input", "swipe", str(round(x)), str(round(start)), str(round(x)), str(round(end)), "350")
            # Even when max==0 the genuine gesture is performed; do not claim
            # a positive scroll or fabricate a larger page for the screenshot.
            try:
                return self.wait_frame(
                    lambda f: f["scroll"] and abs(f["scroll"]["offset"] - f["scroll"]["max"]) < 0.5,
                    after=before if scroll["max"] > 0.5 else None, timeout=8,
                ), before
            except RuntimeError:
                continue
        raise RuntimeError("Landscape did not reach its actual bottom scroll endpoint")

    def record_turns(self, posture, source_name):
        name = posture + "-page-turns"
        video = self.output / (name + ".mp4")
        remote = "/data/local/tmp/" + video.name
        state = json.loads((self.output / (source_name + "-state.json")).read_text())
        build = json.loads((self.output / "build.json").read_text())
        installed = self.shell("pm", "path", PACKAGE).removeprefix("package:")
        assert build["package"] == PACKAGE and re.fullmatch(r"[0-9a-f]{40}", build["commit"])
        assert self.shell("sha256sum", installed).split()[0] == build["sha256"], "Installed APK differs from build.json"
        mode = "single" if posture == "folded" else "spread"
        step = 1 if mode == "single" else 2
        # Reverse first when the seed is already at the end of the edition.
        neighbour = self.page + step if self.page + step <= 851 else self.page - step
        frame = self.dock(False)
        frames = [frame]
        width, height = state["pixelSize"]
        ratio = min(1, 1280 / max(width, height))
        size = [2 * round(v * ratio / 2) for v in (width, height)]
        args = ["screenrecord", "--size", f"{size[0]}x{size[1]}", "--time-limit", "15"]
        if state["physicalDisplayId"] is not None:
            args.extend(["--display-id", state["physicalDisplayId"]])
        setting = "animator_duration_scale"
        old_scale = self.shell("settings", "get", "global", setting)
        self.shell("rm", "-f", remote)
        try:
            self.shell("settings", "put", "global", setting, "1")
            with ThreadPoolExecutor(max_workers=1) as worker:
                recording = worker.submit(self.shell, *args, remote, timeout=21)
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    length = self.shell("stat", "-c", "%s", remote, check=False)
                    if length.isdigit() and int(length) > 0:
                        break
                    if recording.done():
                        recording.result()
                        raise AssertionError("Screen recording ended before the first turn")
                    time.sleep(.15)
                else:
                    raise RuntimeError("Screen recorder did not create its MP4 header")
                time.sleep(.4)
                for target in (neighbour, self.page):
                    before = self.device_clock()
                    self.shell("input", "-d", state["focusedDisplayId"], "swipe",
                               *turn_swipe(frame, target > frame["focusedPage"]), 650)
                    frame = self.wait_frame(lambda f: f["mode"] == mode and f["zoom"] == frames[0]["zoom"],
                                            after=before, timeout=4, expected_page=target)
                    frames.append(frame)
                if recording.done():
                    recording.result()
                    raise AssertionError("Screen recording ended before both turns settled")
                recording.result()
            assert foreground_window(self.shell("dumpsys", "window")) == {
                "displayId": state["focusedDisplayId"], "package": PACKAGE,
            }, "Window focus changed during page turns"
            self.adb("pull", remote, video)
            probe = subprocess.run(
                ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                 "stream=width,height,duration,nb_frames", "-of", "json", str(video)],
                check=True, capture_output=True, timeout=15,
            )
            stream, = json.loads(probe.stdout)["streams"]
            assert [stream["width"], stream["height"]] == size, "Unexpected turn recording dimensions"
            assert 1 < float(stream["duration"]) <= 16 and int(stream["nb_frames"]) >= 8, "Missing turn video frames"
            write_json(self.output / (name + ".json"), {
                "video": video.name, "commit": build["commit"], "apkSha256": build["sha256"],
                "sourceCapture": source_name, "stream": stream, "settledFrames": frames,
            })
        finally:
            if old_scale == "null":
                self.shell("settings", "delete", "global", setting)
            else:
                self.shell("settings", "put", "global", setting, old_scale)
            self.shell("rm", "-f", remote)

    def diagnostics(self, label, error):
        path = self.output / ("failure-" + label)
        path.mkdir(exist_ok=True)
        (path / "error.txt").write_text(str(error) + "\n")
        commands = {
            "logcat.txt": lambda: self.adb("logcat", "-d", "-t", "1200"),
            "window.txt": lambda: self.shell("dumpsys", "window"),
            "display.txt": lambda: self.shell("dumpsys", "display"),
            "device-state.txt": lambda: self.shell("cmd", "device_state", "state"),
            "hinge.txt": lambda: self.adb("emu", "sensor", "get", "hinge-angle0"),
            "geometry.json": lambda: self.run_as("cat", GEOMETRY),
        }
        for name, read in commands.items():
            try:
                (path / name).write_text(read() + "\n")
            except Exception as exc:
                (path / (name + ".error.txt")).write_text(str(exc) + "\n")
        try:
            display_ids = self.shell("dumpsys", "SurfaceFlinger", "--display-id")
            (path / "physical-displays.txt").write_text(display_ids + "\n")
            ids = list(dict.fromkeys(re.findall(r"\bDisplay\s+(\d+)", display_ids)))
            assert ids, "No physical display IDs available for diagnostic screenshots"
            # The default multi-display screencap prefixes stdout with warning
            # text, producing an invalid PNG. Select each physical display and
            # validate its bytes before keeping it as reviewable evidence.
            for display_id in ids:
                try:
                    raw = self.adb("exec-out", f"screencap -p -d {display_id}", binary=True)
                    with Image.open(io.BytesIO(raw)) as png:
                        assert png.format == "PNG", "Diagnostic capture is not PNG"
                        png.verify()
                    (path / f"screen-{display_id}.png").write_bytes(raw)
                except Exception as exc:
                    (path / f"screen-{display_id}.error.txt").write_text(str(exc) + "\n")
        except Exception as exc:
            (path / "screen.error.txt").write_text(str(exc) + "\n")

    def run(self, record_turns=False):
        if record_turns and (not 2 <= self.page <= 850 or self.page % 2):
            raise ValueError("Use an even file page from 2–850 for a recording that returns to the exact seed by swipe")
        self.prepare()
        recordings = []
        for posture in POSTURES:
            try:
                after = self.posture(posture)
                minimum = 70 if posture in ("folded", "unfolded-portrait") else 60
                self.zoom(minimum)
                source_name = f"{posture}-min-{minimum}"
                # Reproduce the proven comparison baseline rather than racing
                # the reader’s normal ten-second auto-hide timer.
                initial = self.capture(
                    source_name, posture, minimum, after,
                    expanded=posture in ("unfolded-portrait", "half-open-book"),
                )
                if record_turns and posture in TURN_POSTURES:
                    self.record_turns(posture, source_name)
                    recordings.append(posture)
                self.zoom(100)
                maximum = self.capture(f"{posture}-max-100", posture, 100, after, before=initial, expanded=True)
                if posture == "folded":
                    collapsed_after = self.device_clock()
                    self.dock(False)
                    self.capture("folded-max-100-collapsed", posture, 100, collapsed_after, phase="collapsed", before=maximum, expanded=False)
                elif posture == "unfolded-landscape":
                    endpoint, scrolled_after = self.bottom()
                    # max==0 may legitimately publish no new geometry after a
                    # scroll. Native state, the actual gesture, and current PNG
                    # still prove the endpoint; retain the posture freshness gate.
                    endpoint_after = scrolled_after if endpoint["scroll"]["max"] > 0.5 else after
                    self.capture("unfolded-landscape-max-100-bottom", posture, 100, endpoint_after, phase="bottom", before=maximum, expanded=False)
            except Exception as exc:
                self.failures.append({"posture": posture, "error": str(exc)})
                self.diagnostics(posture, exc)
                print(f"FAIL {self.profile} {posture}: {exc}", file=sys.stderr, flush=True)
        report = {
            "profile": self.profile, "emulation": "samsung-dimensions-stock-android",
            "page": self.page, "expectedCaptures": 10, "completed": self.completed,
            "failures": self.failures, "verified": not self.failures and len(self.completed) == 10,
        }
        if record_turns:
            report["turnRecordings"] = recordings
            report["verified"] &= tuple(recordings) == TURN_POSTURES
        write_json(self.output / "qa-result.json", report)
        assert report["verified"], "Android foldable verification failed; see native diagnostics"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--profile", choices=PROFILES, required=True)
    parser.add_argument("--profile-metadata", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--page", type=int, default=6)
    parser.add_argument("--record-turns", action="store_true",
                        default=os.environ.get("READER_QA_RECORD_TURNS") == "1",
                        help="Record both turn directions using an even seed page (READER_QA_RECORD_TURNS=1)")
    args = parser.parse_args()
    assert 1 <= args.page < 851
    capture = Capture(args.serial, args.profile, json.loads(args.profile_metadata.read_text()), args.output, args.page)
    try:
        capture.run(record_turns=args.record_turns)
    except Exception as exc:
        capture.diagnostics("fatal", exc)
        raise


if __name__ == "__main__":
    main()
