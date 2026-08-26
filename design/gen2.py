#!/usr/bin/env python3
"""Generation 2 — silhouette, second pass. Still monochrome.

Two families carried forward from gen 1:

  gen2a-*  cluster. It collapsed into a flower blob by 20px, so every variant
           here is an attempt to buy it air, hierarchy, or a hole — the three
           things that keep a dot arrangement distinct when the dots merge.
  gen2b-*  iris. It already survives; these resolve bead count, the pupil, and
           whether the ring wants to be threaded.
"""

import math
import pathlib

OUT = pathlib.Path(__file__).parent / "marks"
TILE = "#F2F3F7"
INK = "#101018"

HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" '
        'viewBox="0 0 64 64">')


def write(name: str, body: str) -> None:
    svg = (f"{HEAD}\n"
           f'  <rect width="64" height="64" rx="14" fill="{TILE}"/>\n'
           f"{body}\n</svg>\n")
    (OUT / f"{name}.svg").write_text(svg, encoding="utf-8")


def circle(cx, cy, r):
    return f'  <circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="{INK}"/>'


def ring_points(n, cx, cy, r, start_deg=-90):
    """Evenly spaced points on a ring. Computed, never typed — the gaps between
    beads are the whole silhouette, and hand-placed ones drift."""
    for i in range(n):
        a = math.radians(start_deg + i * 360 / n)
        yield cx + r * math.cos(a), cy + r * math.sin(a)


CX = CY = 32.0

# ---------------------------------------------------------------- cluster ---

def c_air():
    """Same seven beads, more space between them."""
    p = [circle(CX, CY, 6.1)]
    p += [circle(x, y, 6.1) for x, y in ring_points(6, CX, CY, 17.2)]
    return "\n".join(p)


def c_hollow():
    """Six beads, no centre. The hole is what reads at 16px."""
    return "\n".join(circle(x, y, 7.0) for x, y in ring_points(6, CX, CY, 17.6))


def c_five():
    """Fewer, bigger beads. Nothing to merge."""
    p = [circle(CX, CY, 8.0)]
    p += [circle(x, y, 8.0) for x, y in ring_points(4, CX, CY, 16.4, -45)]
    return "\n".join(p)


def c_focal():
    """One bead dominant, six small — hierarchy instead of an even field."""
    p = [circle(CX, CY, 9.6)]
    p += [circle(x, y, 5.2) for x, y in ring_points(6, CX, CY, 18.6)]
    return "\n".join(p)


def c_stack():
    """Triangular packing: 1-2-3. A triangle silhouette, not a disc."""
    rows = [(1, 15.0), (2, 31.0), (3, 47.0)]
    r, step = 6.6, 15.4
    p = []
    for count, y in rows:
        x0 = CX - step * (count - 1) / 2
        for i in range(count):
            p.append(circle(x0 + i * step, y, r))
    return "\n".join(p)


# ------------------------------------------------------------------- iris ---

def i_eight():
    """Gen 1 as drawn, for reference."""
    p = [circle(x, y, 5.1) for x, y in ring_points(8, CX, CY, 19.0)]
    p.append(circle(CX, CY, 7.4))
    return "\n".join(p)


def i_six():
    """Six fatter beads. Bigger elements, bigger gaps."""
    p = [circle(x, y, 6.6) for x, y in ring_points(6, CX, CY, 18.4)]
    p.append(circle(CX, CY, 8.0))
    return "\n".join(p)


def i_open():
    """No pupil. The aperture itself is the mark."""
    return "\n".join(circle(x, y, 5.8) for x, y in ring_points(8, CX, CY, 18.6))


def i_focal():
    """One bead on the ring larger than the rest — the issue being watched."""
    pts = list(ring_points(7, CX, CY, 18.6))
    p = [circle(x, y, 5.2) for x, y in pts[1:]]
    p.append(circle(pts[0][0], pts[0][1], 7.6))
    p.append(circle(CX, CY, 7.0))
    return "\n".join(p)


def i_threaded():
    """Beads threaded on a ring: the gen-1 strand closed into a necklace."""
    p = [f'  <circle cx="{CX}" cy="{CY}" r="18.4" fill="none" stroke="{INK}" '
         'stroke-width="2.2"/>']
    p += [circle(x, y, 5.4) for x, y in ring_points(8, CX, CY, 18.4)]
    p.append(circle(CX, CY, 6.6))
    return "\n".join(p)


FAMILIES = [
    ("gen2a", [("air", c_air), ("hollow", c_hollow), ("five", c_five),
               ("focal", c_focal), ("stack", c_stack)]),
    ("gen2b", [("eight", i_eight), ("six", i_six), ("open", i_open),
               ("focal", i_focal), ("threaded", i_threaded)]),
]

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("gen2*-*.svg"):
        old.unlink()
    n = 0
    for prefix, members in FAMILIES:
        for i, (name, fn) in enumerate(members, 1):
            write(f"{prefix}-{i}-{name}", fn())
            n += 1
    print(f"wrote {n} marks to {OUT}")
