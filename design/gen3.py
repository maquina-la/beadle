#!/usr/bin/env python3
"""Generation 3 — the bead becomes a hexagon. Still monochrome.

One variable changes from gen 2: bead form. Hexagons tessellate, so the ring
that won gen 2 can now be a real honeycomb with seams instead of a scatter of
discs — and the open centre becomes a cell, not a gap.

Every vertex is computed. A honeycomb whose seams drift by a degree reads as
sloppy at 128px and as mush at 24px, and it looks like a design problem when it
is arithmetic.
"""

import math
import pathlib

OUT = pathlib.Path(__file__).parent / "marks"
TILE = "#F2F3F7"
INK = "#101018"

HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" '
        'viewBox="0 0 64 64">')
CX = CY = 32.0

# Honeycomb geometry. For a flat-top hexagon of circumradius R, neighbours sit
# at distance sqrt(3)*R, at 60-degree steps starting from straight up. SEAM
# shrinks each cell off that pitch so the seams are visible rather than welded.
PITCH = 16.44
SEAM = 0.92
R = PITCH / math.sqrt(3) * SEAM


def write(name: str, body: str) -> None:
    svg = (f"{HEAD}\n"
           f'  <rect width="64" height="64" rx="14" fill="{TILE}"/>\n'
           f"{body}\n</svg>\n")
    (OUT / f"{name}.svg").write_text(svg, encoding="utf-8")


def hex_path(cx, cy, r, rot_deg=0.0, round_frac=0.20):
    """A hexagon with softened corners, as a path.

    round_frac is the fraction of each edge given over to the corner; the
    corner itself is a quadratic through the true vertex, which stays crisp
    enough to read as a hexagon at 16px while losing the needle points that
    alias into grey.
    """
    pts = [(cx + r * math.cos(math.radians(rot_deg + 60 * i)),
            cy + r * math.sin(math.radians(rot_deg + 60 * i))) for i in range(6)]
    d = []
    for i, (px, py) in enumerate(pts):
        ax, ay = pts[(i - 1) % 6]
        bx, by = pts[(i + 1) % 6]
        inx, iny = px + (ax - px) * round_frac, py + (ay - py) * round_frac
        outx, outy = px + (bx - px) * round_frac, py + (by - py) * round_frac
        d.append(("M" if i == 0 else "L") + f"{inx:.2f} {iny:.2f}")
        d.append(f"Q{px:.2f} {py:.2f} {outx:.2f} {outy:.2f}")
    return "".join(d) + "Z"


def hexagon(cx, cy, r, rot=0.0, round_frac=0.20, fill=INK):
    return f'  <path d="{hex_path(cx, cy, r, rot, round_frac)}" fill="{fill}"/>'


def comb_points(pitch=PITCH, start_deg=-90):
    """The six neighbours of a honeycomb cell, one of them straight up."""
    for i in range(6):
        a = math.radians(start_deg + 60 * i)
        yield CX + pitch * math.cos(a), CY + pitch * math.sin(a)


# 1. Comb — seven cells, the hexgrid the app ships with, drawn as an actual
#    honeycomb instead of seven loose discs.
def comb():
    p = [hexagon(CX, CY, R)]
    p += [hexagon(x, y, R) for x, y in comb_points()]
    return "\n".join(p)


# 2. Hole — the gen 2 winner in hex. Six cells, open centre.
def hole():
    return "\n".join(hexagon(x, y, R) for x, y in comb_points())


# 3. Pupil — hex ring around a round bead. The one circle in the mark is the
#    thing being watched.
def pupil():
    p = [hexagon(x, y, R) for x, y in comb_points()]
    p.append(f'  <circle cx="{CX}" cy="{CY}" r="6.6" fill="{INK}"/>')
    return "\n".join(p)


# 4. Rosette — eight hexes turned to face the centre. An aperture rather than a
#    comb; breaks the honeycomb but gains rotational tension.
def rosette():
    p = []
    for i in range(8):
        a = math.radians(-90 + i * 45)
        x, y = CX + 18.6 * math.cos(a), CY + 18.6 * math.sin(a)
        p.append(hexagon(x, y, 6.4, rot=math.degrees(a)))
    return "\n".join(p)


# 5. Shell — one hexagon as the container, three cells inside it. The frame
#    reading: a monitor with beads in it.
def shell():
    outline = (f'  <path d="{hex_path(CX, CY, 25.0, -90, 0.16)}" fill="none" '
               f'stroke="{INK}" stroke-width="4.2" stroke-linejoin="round"/>')
    p = [outline]
    for a in (-90, 30, 150):
        rad = math.radians(a)
        p.append(hexagon(CX + 9.6 * math.cos(rad), CY + 9.6 * math.sin(rad),
                         7.0, rot=-90))
    return "\n".join(p)


# 6. Stack — honeycomb triangle, 1 over 2 over 3. Keeps the distinctive
#    silhouette from gen 2 but tessellated.
def stack():
    rows = [(1, -PITCH * math.sqrt(3) / 2), (2, 0.0),
            (3, PITCH * math.sqrt(3) / 2)]
    r = R * 0.86
    p = []
    for count, dy in rows:
        x0 = CX - PITCH * (count - 1) / 2
        for i in range(count):
            p.append(hexagon(x0 + i * PITCH, CY + dy * 0.86, r, rot=-90))
    return "\n".join(p)


# 7. Negative — one solid hexagon with three beads punched out of it. The
#    heaviest silhouette on the sheet, and the only one that is a shape rather
#    than an arrangement.
def negative():
    holes = []
    for a in (-90, 30, 150):
        rad = math.radians(a)
        hx, hy = CX + 10.4 * math.cos(rad), CY + 10.4 * math.sin(rad)
        # Reversed circle, drawn as two arcs, so evenodd punches it out.
        holes.append(f"M{hx - 6.2:.2f} {hy:.2f}"
                     f"a6.2 6.2 0 1 0 12.4 0a6.2 6.2 0 1 0 -12.4 0Z")
    d = hex_path(CX, CY, 27.0, -90, 0.18) + "".join(holes)
    return f'  <path d="{d}" fill="{INK}" fill-rule="evenodd"/>'


MARKS = [("comb", comb), ("hole", hole), ("pupil", pupil),
         ("rosette", rosette), ("shell", shell), ("stack", stack),
         ("negative", negative)]

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("gen3-*.svg"):
        old.unlink()
    for i, (name, fn) in enumerate(MARKS, 1):
        write(f"gen3-{i}-{name}", fn())
    print(f"wrote {len(MARKS)} marks to {OUT}")
