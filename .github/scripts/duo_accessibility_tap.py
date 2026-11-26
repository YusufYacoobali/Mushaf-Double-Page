#!/usr/bin/env python3
"""Resolve unique Flutter accessibility controls to Duo active-screen points.

Flutter often exposes a tooltip twice, separated by a newline. The shorthand
`duoctl tap --label "Open navigation"` requires an exact label match and
therefore fails even when the button is present. Use its geometric centre.
"""
import json
import sys


def find_center(path: str, target: str) -> tuple[float, float]:
    with open(path, encoding="utf-8") as file:
        elements = json.load(file)
    buttons = [
        item for item in elements
        if item.get("type") == "Button"
        and target in [line.strip() for line in str(item.get("label") or "").splitlines()]
    ]
    if not buttons:
        labels = [item.get("label") for item in elements if item.get("label")]
        raise ValueError(f"Button {target!r} not found; visible labels: {labels}")
    if len(buttons) != 1:
        raise ValueError(f"Ambiguous button {target!r}: {len(buttons)} matches")
    frame = buttons[0].get("frame", {})
    x = float(frame["x"]) + float(frame["width"]) / 2
    y = float(frame["y"]) + float(frame["height"]) / 2
    return x, y


if __name__ == "__main__":
    try:
        x, y = find_center(*sys.argv[1:3])
        print(f"{x:.2f} {y:.2f}")
    except (ValueError, KeyError, TypeError) as exc:
        print(f"Duo accessibility error: {exc}", file=sys.stderr)
        sys.exit(1)
