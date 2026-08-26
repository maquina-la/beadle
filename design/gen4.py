#!/usr/bin/env python3
"""Generation 4 — micro-variants of the two finalists. Still monochrome.

  gen4a-*  negative: a solid hexagon with beads punched out.
  gen4b-*  shell: a hexagon frame with beads inside it.

What is being decided here is geometry, not style: bead count, hole size, wall
weight, and whether the hexagon is pointy-top or flat-top. All four of those
change what survives at 16px, and none of them are visible at 128.
"""

import math
import pathlib

from gen3 import CX, CY, INK, hex_path, hexagon, write

OUT = pathlib.Path(__file__).parent / "marks"


def punch_circle(cx, cy, r):
    """A circle as two arcs, appended to a path that fills with evenodd."""
    return (f"M{cx - r:.2f} {cy:.2f}a{r:.2f} {r:.2f} 0 1 0 {2 * r:.2f} 0"
            f"a{r:.2f} {r:.2f} 0 1 0 {-2 * r:.2f} 0Z")


def at(angle_deg, dist):
    a = math.radians(angle_deg)
    return CX + dist * math.cos(a), CY + dist * math.sin(a)


def solid(hex_r, rot, round_frac, holes):
    d = hex_path(CX, CY, hex_r, rot, round_frac) + "".join(holes)
    return f'  <path d="{d}" fill="{INK}" fill-rule="evenodd"/>'


# ------------------------------------------------------- negative variants ---
# Pointy-top hexagon, three beads. Angles -90/30/150 put one bead under the
# apex, which is what keeps the mark from reading as a rotated triangle.
TRI = (-90, 30, 150)


def n_control():
    return solid(27.0, -90, 0.18,
                 [punch_circle(*at(a, 10.4), 6.2) for a in TRI])


def n_open():
    """Bigger beads, thinner walls. More bead, less hexagon."""
    return solid(27.0, -90, 0.18,
                 [punch_circle(*at(a, 11.2), 7.5) for a in TRI])


def n_flat():
    """Flat-top hexagon. Sits differently in a menu bar row than pointy-top."""
    return solid(27.0, 0, 0.18,
                 [punch_circle(*at(a, 10.4), 6.2) for a in (-60, 60, 180)])


def n_hexbeads():
    """Beads punched as hexagons: one shape language, no circles at all."""
    holes = [hex_path(*at(a, 10.6), 7.1, -90, 0.22) for a in TRI]
    return solid(27.0, -90, 0.18, holes)


def n_four():
    """Three around one — a honeycomb knocked out of the tile."""
    holes = [punch_circle(*at(a, 12.6), 5.6) for a in TRI]
    holes.append(punch_circle(CX, CY, 5.6))
    return solid(27.0, -90, 0.18, holes)


# ---------------------------------------------------------- shell variants ---

def frame(r, width, rot=-90, round_frac=0.16):
    return (f'  <path d="{hex_path(CX, CY, r, rot, round_frac)}" fill="none" '
            f'stroke="{INK}" stroke-width="{width}" stroke-linejoin="round"/>')


def s_control():
    p = [frame(25.0, 4.2)]
    p += [hexagon(*at(a, 9.6), 7.0, rot=-90) for a in TRI]
    return "\n".join(p)


def s_thin():
    """Lighter wall, fatter cells — the wall stops competing with the beads."""
    p = [frame(25.4, 3.0)]
    p += [hexagon(*at(a, 10.0), 7.8, rot=-90) for a in TRI]
    return "\n".join(p)


def s_eye():
    """One cell. The fewest elements anything on this sheet can have."""
    return "\n".join([frame(25.0, 4.4), hexagon(CX, CY, 9.6, rot=-90)])


def s_flat():
    p = [frame(25.0, 4.2, rot=0)]
    p += [hexagon(*at(a, 9.6), 7.0, rot=0) for a in (-60, 60, 180)]
    return "\n".join(p)


def s_circles():
    """Hex frame, round beads. The beads stay beads; the frame is the monitor."""
    p = [frame(25.0, 4.2)]
    p += [f'  <circle cx="{x:.2f}" cy="{y:.2f}" r="6.6" fill="{INK}"/>'
          for x, y in (at(a, 9.8) for a in TRI)]
    return "\n".join(p)


FAMILIES = [
    ("gen4a", [("control", n_control), ("open", n_open), ("flat", n_flat),
               ("hexbeads", n_hexbeads), ("four", n_four)]),
    ("gen4b", [("control", s_control), ("thin", s_thin), ("eye", s_eye),
               ("flat", s_flat), ("circles", s_circles)]),
]

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("gen4*-*.svg"):
        old.unlink()
    n = 0
    for prefix, members in FAMILIES:
        for i, (name, fn) in enumerate(members, 1):
            write(f"{prefix}-{i}-{name}", fn())
            n += 1
    print(f"wrote {n} marks to {OUT}")
