#!/usr/bin/env python3
"""Generation 1 — silhouettes for Beadle, monochrome only.

Six directions for a beads monitor: strand, cluster, iris, dependency graph,
abacus, monogram. Each is emitted as a light tile with a black glyph so it can
be read on all three grounds of the contact sheet; the tile is constant across
candidates, so what varies is only the silhouette.
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
           f"{body}\n"
           f"</svg>\n")
    (OUT / f"{name}.svg").write_text(svg, encoding="utf-8")


def circle(cx, cy, r, fill=INK):
    return f'  <circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="{fill}"/>'


def line(x1, y1, x2, y2, w=3.0):
    return (f'  <path d="M{x1:.2f} {y1:.2f}L{x2:.2f} {y2:.2f}" stroke="{INK}" '
            f'stroke-width="{w:.2f}" stroke-linecap="round" fill="none"/>')


def ring_points(n, cx, cy, r, start_deg=-90):
    for i in range(n):
        a = math.radians(start_deg + i * 360 / n)
        yield cx + r * math.cos(a), cy + r * math.sin(a)


# 1. Strand — three beads threaded on a wire. The most literal reading of
#    "beads"; the wire gives it a direction the cluster does not have.
def strand():
    parts = [f'  <path d="M11 40Q32 14 53 24" stroke="{INK}" stroke-width="3" '
             'stroke-linecap="round" fill="none"/>']
    for cx, cy, r in ((14.5, 36.5, 7.0), (32.0, 24.0, 7.6), (50.0, 25.5, 7.0)):
        parts.append(circle(cx, cy, r))
    return "\n".join(parts)


# 2. Cluster — the hexagonal packing the app ships with today, drawn properly.
#    Included as the control: it is the direction to beat.
def cluster():
    parts = [circle(32, 32, 7.2)]
    for x, y in ring_points(6, 32, 32, 15.4, start_deg=-90):
        parts.append(circle(x, y, 7.2))
    return "\n".join(parts)


# 3. Iris — beads arranged as an aperture around a pupil. Beads plus the act of
#    watching, which is what the app actually does.
def iris():
    parts = []
    for x, y in ring_points(8, 32, 32, 19.0):
        parts.append(circle(x, y, 5.1))
    parts.append(circle(32, 32, 7.4))
    return "\n".join(parts)


# 4. Graph — a dependency chain. Beads is an issue tracker with blockers; this
#    says tracker more than it says jewellery.
def graph():
    nodes = [(32, 13.5, 6.2), (16, 32, 6.2), (48, 32, 6.2), (32, 50.5, 6.2)]
    parts = [line(32, 13.5, 16, 32, 3.2), line(32, 13.5, 48, 32, 3.2),
             line(16, 32, 32, 50.5, 3.2), line(48, 32, 32, 50.5, 3.2)]
    parts += [circle(x, y, r) for x, y, r in nodes]
    return "\n".join(parts)


# 5. Abacus — beads on rails at different positions. Reads as counts and state,
#    which is the menu bar's whole job.
def abacus():
    parts = []
    rows = [(21.0, [17.0, 27.0]), (32.0, [40.0]), (43.0, [22.0, 32.0, 42.0])]
    for y, xs in rows:
        parts.append(line(12, y, 52, y, 2.6))
    for y, xs in rows:
        for x in xs:
            parts.append(circle(x, y, 5.4))
    return "\n".join(parts)


# 6. Monogram — a B whose bowls are beads. Carries the name at sizes where any
#    arrangement of dots turns into a generic blob.
def monogram():
    stem = (f'  <path d="M18 12.5V51.5" stroke="{INK}" stroke-width="7.5" '
            'stroke-linecap="round" fill="none"/>')
    parts = [stem, circle(31.5, 22.0, 9.8), circle(33.5, 42.0, 9.8)]
    return "\n".join(parts)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("gen1-*.svg"):
        old.unlink()
    for i, (name, fn) in enumerate(
            [("strand", strand), ("cluster", cluster), ("iris", iris),
             ("graph", graph), ("abacus", abacus), ("monogram", monogram)], 1):
        write(f"gen1-{i}-{name}", fn())
    print(f"wrote 6 marks to {OUT}")
