#!/usr/bin/env python3
"""Generation 5 — colour. One hue per tile, everything else held constant.

Geometry is gen4a-2: the hexagon in white, three beads punched through to the
tile colour underneath. Treatment is a single soft top-down gradient, the same
angle and the same lift in every tile, so what is being compared is hue and
nothing else.

Gradient ids are namespaced per file. Ids go global the moment two of these are
inlined into one page, and a shared `tile` would mean the last icon silently
repaints every earlier one.
"""

import math
import pathlib

from gen3 import CX, CY, hex_path
from gen4 import at, punch_circle

OUT = pathlib.Path(__file__).parent / "marks"

HUES = [
    ("azure", "#2F6BF2"),     # what the app tints with today
    ("indigo", "#4B57E0"),
    ("violet", "#7C3AED"),
    ("teal", "#0E9AA0"),
    ("emerald", "#0FA968"),
    ("amber", "#EA9B0B"),
    ("coral", "#EE5F3E"),
    ("graphite", "#31353E"),
]

TRI = (-90, 30, 150)


def lift(hexcolor: str, amount: float) -> str:
    r, g, b = (int(hexcolor[i:i + 2], 16) for i in (1, 3, 5))
    r, g, b = (round(c + (255 - c) * amount) for c in (r, g, b))
    return f"#{r:02X}{g:02X}{b:02X}"


def tile(name: str, base: str) -> str:
    top, bottom = lift(base, 0.22), base
    mark = hex_path(CX, CY, 27.0, -90, 0.18) + "".join(
        punch_circle(*at(a, 11.2), 7.5) for a in TRI)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" '
        'viewBox="0 0 64 64">\n'
        f'  <defs><linearGradient id="{name}-tile" x1="0" y1="0" x2="0.28" y2="1">\n'
        f'    <stop offset="0" stop-color="{top}"/>\n'
        f'    <stop offset="1" stop-color="{bottom}"/>\n'
        '  </linearGradient></defs>\n'
        f'  <rect width="64" height="64" rx="14" fill="url(#{name}-tile)"/>\n'
        f'  <path d="{mark}" fill="#FFFFFF" fill-rule="evenodd"/>\n'
        '</svg>\n')


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("gen5-*.svg"):
        old.unlink()
    for i, (name, base) in enumerate(HUES, 1):
        (OUT / f"gen5-{i}-{name}.svg").write_text(tile(name, base),
                                                  encoding="utf-8")
    print(f"wrote {len(HUES)} tiles to {OUT}")
