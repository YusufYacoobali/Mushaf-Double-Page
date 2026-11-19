#!/usr/bin/env python3
"""Pair a real simulator screenshot with stable, settled reader geometry."""

import argparse
import json
from pathlib import Path
import subprocess
import time

from verify_fitted_capture import MODES, assert_capture_state, bounds, check_geometry, check_pair, verify


def read(path):
    return json.loads(path.read_text())


def capture(source, png, posture, percent, after, phase, before, state, udid, expected_page=None):
    layout = png.with_suffix(".layout.json")
    previous = read(before) if before else None
    mode = MODES[posture]
    deadline = time.monotonic() + 35
    error = "No geometry available"
    while time.monotonic() < deadline:
        try:
            frame = read(source)
            assert_capture_state(frame, percent, mode, after, expected_page)
            check_geometry(frame, posture, phase, state)
            if previous:
                check_pair(previous, frame, phase)
            if (
                posture == "duo-folded"
                and percent == 100
                and phase == "initial"
                and not frame["navigationExpanded"]
            ):
                tap_tab(frame["controls"]["Open navigation"])
                time.sleep(0.5)
                continue
            command = (
                ["xcrun", "simctl", "io", udid, "screenshot"]
                if posture.startswith("ipad-mini")
                else ["duoctl", "screenshot"]
            )
            subprocess.run(command + [str(png)], check=True, timeout=30)
            immediately_after = read(source)
            # Allow an in-progress hide/scroll to publish its settled state.
            time.sleep(0.5)
            assert immediately_after == frame == read(source), "reader changed during screenshot"
            layout.write_text(json.dumps(frame, indent=2) + "\n")
            verify(
                png,
                layout,
                percent,
                mode,
                after,
                posture=posture,
                phase=phase,
                before=previous,
                state=state,
                expected_page=expected_page,
            )
            print(
                json.dumps(
                    {
                        k: frame[k]
                        for k in (
                            "viewport",
                            "padding",
                            "viewPadding",
                            "frameworkFeatures",
                            "native",
                            "sizing",
                            "navigationExpanded",
                            "controls",
                            "pages",
                            "scroll",
                        )
                    },
                    sort_keys=True,
                )
            )
            return
        except (OSError, ValueError, KeyError, TypeError, AssertionError) as exc:
            error = repr(exc)
            time.sleep(0.3)
    if source.exists():
        diagnostic = source.read_text()
        layout.with_suffix(".failed.json").write_text(diagnostic)
        print(f"Last observed reader geometry: {diagnostic}", flush=True)
    raise RuntimeError(f"{png}: no matching stable capture within 35s: {error}")


def tap_tab(tab):
    x, y = tab["left"] + tab["width"] / 2, tab["top"] + tab["height"] / 2
    subprocess.run(["duoctl", "tap", str(round(x)), str(round(y))], check=True, timeout=30)


def swipe_to_bottom(frame):
    # Touch the currently focused leaf. Both leaves share this viewport.
    page = frame["pages"][str(frame["focusedPage"])]
    l, t, r, b = bounds(frame["scroll"]["viewport"])
    x = round(page["left"] + page["width"] * 0.45)
    y = round(t + (b - t) * 0.7)
    target = round(t + (b - t) * 0.25)
    assert l < x < r
    nl, nt, nr, nb = bounds(frame["navigation"])
    assert not (nl <= x <= nr and target <= nb and y >= nt), "gesture intersects dock"
    subprocess.run(
        ["duoctl", "swipe", str(x), str(y), str(x), str(target), "--duration", ".3"],
        check=True,
        timeout=30,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("png", type=Path)
    parser.add_argument("posture", choices=MODES)
    parser.add_argument("percent", type=int)
    parser.add_argument("after", type=float)
    parser.add_argument("--phase", choices=["initial", "collapsed", "bottom"], default="initial")
    parser.add_argument("--before", type=Path)
    parser.add_argument("--state", type=Path)
    parser.add_argument("--udid")
    parser.add_argument("--page", type=int)
    args = parser.parse_args()
    assert args.state or args.posture.startswith("ipad-mini"), "Duo capture requires external native state"
    if args.phase != "initial":
        assert args.before and args.state
        if args.phase == "bottom":
            args.after = time.time()
            swipe_to_bottom(read(args.source))
        # For the folded endpoint, observe the actual ten-second auto-hide.
        # Sending an input while the tab moves can select the ayah underneath.
    capture(
        args.source,
        args.png,
        args.posture,
        args.percent,
        args.after,
        args.phase,
        args.before,
        read(args.state) if args.state else None,
        args.udid,
        args.page,
    )
