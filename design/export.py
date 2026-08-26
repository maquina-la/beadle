#!/usr/bin/env python3
"""Export the winning mark (gen7-1) as the files the project actually ships.

    design/out/beadle-mark.svg          glyph alone, currentColor
    design/out/beadle-icon.svg          1024pt macOS app tile, graphite
    design/out/beadle-lockup-light.svg  mark + wordmark, ink on light
    design/out/beadle-lockup-dark.svg   mark + wordmark, light on dark
    design/out/AppIcon.icns             built from per-size renders
    design/out/social-preview.png       1280x640 for the GitHub repo card

The wordmark is converted to outlines, so no lockup file depends on Sora being
installed anywhere. Run with the venv that has fonttools:

    scratchpad/venv/bin/python design/export.py
"""

import math
import pathlib
import shutil
import subprocess
import tempfile

HERE = pathlib.Path(__file__).parent
OUT = HERE / "out"
FONT = HERE / "marks" / "fonts" / "sora-700.woff2"
CHROME = ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

GRAPHITE = "#31353E"
GRAPHITE_TOP = "#565B66"
INK = "#1B1E24"
PAPER = "#F2F3F7"

# ------------------------------------------------------------- geometry ---
# gen7-3: flat-top hexagon, three hexagonal beads turned 30 degrees against it,
# sitting on the edge midpoints, drawn fat so the beads carry the mark and the
# walls stay just thick enough to hold at 16px. Ratios are held to the outer
# circumradius so the mark can be drawn at any size without redrawing it.
BEAD_R = 8.0 / 27.0
BEAD_DIST = 11.0 / 27.0
TRI = (-90, 30, 150)


def hex_path(cx, cy, r, rot_deg=0.0, round_frac=0.20):
    pts = [(cx + r * math.cos(math.radians(rot_deg + 60 * i)),
            cy + r * math.sin(math.radians(rot_deg + 60 * i))) for i in range(6)]
    d = []
    for i, (px, py) in enumerate(pts):
        ax, ay = pts[(i - 1) % 6]
        bx, by = pts[(i + 1) % 6]
        d.append(("M" if i == 0 else "L")
                 + f"{px + (ax - px) * round_frac:.3f} "
                   f"{py + (ay - py) * round_frac:.3f}")
        d.append(f"Q{px:.3f} {py:.3f} "
                 f"{px + (bx - px) * round_frac:.3f} "
                 f"{py + (by - py) * round_frac:.3f}")
    return "".join(d) + "Z"


def mark_path(cx, cy, r):
    """Outer hexagon plus three punched beads, filled with evenodd."""
    d = hex_path(cx, cy, r, 0.0, 0.18)
    for a in TRI:
        rad = math.radians(a)
        d += hex_path(cx + r * BEAD_DIST * math.cos(rad),
                      cy + r * BEAD_DIST * math.sin(rad),
                      r * BEAD_R, -90.0, 0.22)
    return d


def mark_svg(fill="currentColor"):
    """The glyph alone. Flat-top, so the box is wider than it is tall."""
    r = 31.0
    w, h = 2 * r + 2, math.sqrt(3) * r + 2
    d = mark_path(w / 2, h / 2, r)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" '
            f'height="{h:.0f}" viewBox="0 0 {w:.0f} {h:.0f}" '
            'role="img" aria-label="Beadle">\n'
            f'  <path d="{d}" fill="{fill}" fill-rule="evenodd"/>\n</svg>\n')


def icon_svg(size=1024):
    """macOS app tile: the rounded square occupies 824/1024 of the canvas, the
    proportion Apple's icon grid expects, with the rest left transparent."""
    tile = size * 824 / 1024
    inset = (size - tile) / 2
    radius = tile * 0.2237
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" '
            f'height="{size}" viewBox="0 0 {size} {size}">\n'
            '  <defs><linearGradient id="beadle-tile" x1="0" y1="0" x2="0.28" y2="1">\n'
            f'    <stop offset="0" stop-color="{GRAPHITE_TOP}"/>\n'
            f'    <stop offset="1" stop-color="{GRAPHITE}"/>\n'
            '  </linearGradient></defs>\n'
            f'  <rect x="{inset:.2f}" y="{inset:.2f}" width="{tile:.2f}" '
            f'height="{tile:.2f}" rx="{radius:.2f}" fill="url(#beadle-tile)"/>\n'
            f'  <path d="{mark_path(size / 2, size / 2, tile * 0.315)}" '
            'fill="#FFFFFF" fill-rule="evenodd"/>\n</svg>\n')


# ------------------------------------------------------------- wordmark ---

def wordmark(text: str, cap_px: float):
    """The word as outlines, plus its advance width.

    Outlines rather than a font-family, so the lockup renders identically in a
    browser, in Preview, and on GitHub, none of which have Sora installed.
    """
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.ttLib import TTFont

    font = TTFont(str(FONT))
    upem = font["head"].unitsPerEm
    cap = font["OS/2"].sCapHeight
    scale = cap_px / cap
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    hmtx = font["hmtx"]

    d, x = [], 0.0
    for ch in text:
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.2f}")
        # y is flipped: font space is up-positive, SVG is down-positive.
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, 0)))
        d.append(pen.getCommands())
        x += hmtx[name][0] * scale
    return "".join(d), x


def lockup_svg(ink: str, ground: str | None = None):
    cap = 40.0
    mark_h = cap / 0.66                      # cap height sets the mark height
    mark_r = mark_h / math.sqrt(3)
    mark_w = 2 * mark_r
    gap = mark_h * 0.42
    pad = mark_h * 0.28

    word, word_w = wordmark("Beadle", cap)
    w = pad * 2 + mark_w + gap + word_w
    h = pad * 2 + mark_h

    bg = (f'  <rect width="{w:.1f}" height="{h:.1f}" rx="{h * 0.16:.1f}" '
          f'fill="{ground}"/>\n') if ground else ""
    baseline = pad + mark_h / 2 + cap / 2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.1f}" '
            f'height="{h:.1f}" viewBox="0 0 {w:.1f} {h:.1f}" '
            'role="img" aria-label="Beadle">\n' + bg +
            f'  <path d="{mark_path(pad + mark_r, pad + mark_h / 2, mark_r)}" '
            f'fill="{ink}" fill-rule="evenodd"/>\n'
            f'  <g transform="translate({pad + mark_w + gap:.2f} '
            f'{baseline:.2f})"><path d="{word}" fill="{ink}"/></g>\n</svg>\n')


def social_svg():
    """1280x640 repo card: tile, wordmark, one line of what the thing is."""
    w, h = 1280, 640
    cap = 76.0
    word, word_w = wordmark("Beadle", cap)
    tile = 200.0
    gap = 54.0
    total = tile + gap + word_w
    x0 = (w - total) / 2
    cy = h / 2 - 26

    sub, sub_w = wordmark("Your Beads work, one click away.", 22.0)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}">\n'
            '  <defs><linearGradient id="beadle-social" x1="0" y1="0" x2="0.4" y2="1">\n'
            '    <stop offset="0" stop-color="#1A1D23"/>\n'
            '    <stop offset="1" stop-color="#0D0F13"/>\n'
            '  </linearGradient></defs>\n'
            f'  <rect width="{w}" height="{h}" fill="url(#beadle-social)"/>\n'
            f'  <rect x="{x0:.1f}" y="{cy - tile / 2:.1f}" width="{tile}" '
            f'height="{tile}" rx="{tile * 0.2237:.1f}" fill="{GRAPHITE}"/>\n'
            f'  <path d="{mark_path(x0 + tile / 2, cy, tile * 0.315)}" '
            'fill="#FFFFFF" fill-rule="evenodd"/>\n'
            f'  <g transform="translate({x0 + tile + gap:.1f} {cy + cap / 2:.1f})">'
            f'<path d="{word}" fill="{PAPER}"/></g>\n'
            f'  <g transform="translate({(w - sub_w) / 2:.1f} {h - 150:.1f})">'
            f'<path d="{sub}" fill="#8A8F9A"/></g>\n</svg>\n')


# ---------------------------------------------------------------- render ---

def render_png(svg_path: pathlib.Path, out_png: pathlib.Path, w: int, h: int):
    """Rasterise with headless Chrome at the exact pixel size.

    Each size is re-rendered from the vector rather than downscaled from 1024:
    a 16px icon that was resampled from a big one arrives soft, which is the
    difference between a crisp menu bar and a smudge.
    """
    page = out_png.with_suffix(".html")
    page.write_text(
        '<!doctype html><meta charset="utf-8">'
        '<style>html,body{margin:0;padding:0;background:transparent}'
        f'img{{display:block;width:{w}px;height:{h}px}}</style>'
        f'<img src="{svg_path.name}">', encoding="utf-8")
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
         "--default-background-color=00000000", f"--window-size={w},{h}",
         f"--screenshot={out_png}", page.as_uri()],
        check=True, capture_output=True)
    page.unlink()


def build_icns(icon_path: pathlib.Path, dest: pathlib.Path):
    sizes = [(16, "16x16", 1), (32, "16x16", 2), (32, "32x32", 1),
             (64, "32x32", 2), (128, "128x128", 1), (256, "128x128", 2),
             (256, "256x256", 1), (512, "256x256", 2), (512, "512x512", 1),
             (1024, "512x512", 2)]
    with tempfile.TemporaryDirectory() as tmp:
        iconset = pathlib.Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        shutil.copy(icon_path, iconset / icon_path.name)
        for px, label, scale in sizes:
            suffix = "@2x" if scale == 2 else ""
            render_png(icon_path, iconset / f"icon_{label}{suffix}.png", px, px)
        (iconset / icon_path.name).unlink()
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(dest)],
                       check=True)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "beadle-mark.svg").write_text(mark_svg(), encoding="utf-8")
    (OUT / "beadle-icon.svg").write_text(icon_svg(), encoding="utf-8")
    (OUT / "beadle-lockup-light.svg").write_text(lockup_svg(INK), encoding="utf-8")
    (OUT / "beadle-lockup-dark.svg").write_text(lockup_svg(PAPER), encoding="utf-8")
    (OUT / "social-preview.svg").write_text(social_svg(), encoding="utf-8")

    build_icns(OUT / "beadle-icon.svg", OUT / "AppIcon.icns")
    render_png(OUT / "social-preview.svg", OUT / "social-preview.png", 1280, 640)
    print("\n".join(sorted(p.name for p in OUT.iterdir())))
