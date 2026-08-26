#!/usr/bin/env python3
"""Generation 7 — hexbeads, flat-top, in graphite. Orientation only.

Colour is settled (graphite) and geometry is settled (hexagon, three hexagonal
beads punched through). What is left is orientation, which is two independent
choices:

  outer hexagon   flat-top (a flat edge up) or pointy-top (a vertex up)
  inner beads     aligned with the outer hexagon, or turned 30 degrees against it

Beads sit on edge midpoints, not on vertices. gen4a-3 put them on the vertices
and the whole mark read as a triangle that had been rotated by mistake.
"""

import pathlib

from gen3 import CX, CY, hex_path
from gen4 import at

OUT = pathlib.Path(__file__).parent / "marks"

GRAPHITE = "#31353E"
GRAPHITE_TOP = "#565B66"
WHITE = "#FFFFFF"

TRI = (-90, 30, 150)          # up, lower-right, lower-left
FLAT, POINTY = 0.0, -90.0     # outer hexagon rotation


def tile(name: str, mark_path: str) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" '
        'viewBox="0 0 64 64">\n'
        f'  <defs><linearGradient id="{name}-tile" x1="0" y1="0" x2="0.28" y2="1">\n'
        f'    <stop offset="0" stop-color="{GRAPHITE_TOP}"/>\n'
        f'    <stop offset="1" stop-color="{GRAPHITE}"/>\n'
        '  </linearGradient></defs>\n'
        f'  <rect width="64" height="64" rx="14" fill="url(#{name}-tile)"/>\n'
        f'  <path d="{mark_path}" fill="{WHITE}" fill-rule="evenodd"/>\n'
        '</svg>\n')


def mark(outer_rot, bead_rot, bead_r=7.1, bead_dist=10.6, outer_r=27.0):
    d = hex_path(CX, CY, outer_r, outer_rot, 0.18)
    for a in TRI:
        d += hex_path(*at(a, bead_dist), bead_r, bead_rot, 0.22)
    return d


VARIANTS = [
    # flat outer, beads turned against it — the reading of "rotated inners"
    ("flat-turned", mark(FLAT, POINTY)),
    # flat outer, beads aligned with it — one honeycomb, one shape language
    ("flat-aligned", mark(FLAT, FLAT)),
    # flat outer, turned beads, fatter — more bead, thinner walls
    ("flat-turned-fat", mark(FLAT, POINTY, bead_r=8.0, bead_dist=11.0)),
    # pointy outer, flat beads — the inverse pairing, for comparison
    ("pointy-turned", mark(POINTY, FLAT)),
]

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("gen7-*.svg"):
        old.unlink()
    for i, (name, d) in enumerate(VARIANTS, 1):
        (OUT / f"gen7-{i}-{name}.svg").write_text(tile(name, d), encoding="utf-8")
    print(f"wrote {len(VARIANTS)} tiles to {OUT}")
