# Beadle brand assets

The mark is a flat-top hexagon with three hexagonal beads punched through it,
each bead turned 30 degrees against the outer shell and sitting on an edge
midpoint. Beads, and a thing with cells you can look into.

## Files

| File | Use |
| --- | --- |
| `out/beadle-mark.svg` | The glyph alone, `currentColor`. Nav bars, favicons, anywhere it inherits a colour. |
| `out/beadle-icon.svg` | The app tile, graphite. The rounded square fills 824/1024 of the canvas, which is the proportion macOS expects. |
| `out/AppIcon.icns` | Built from per-size renders of `beadle-icon.svg`; copied to `packaging/AppIcon.icns` and into the bundle by `scripts/build-app.sh`. |
| `out/beadle-lockup-light.svg` | Mark + wordmark, ink on light. README header. |
| `out/beadle-lockup-dark.svg` | Same, light on dark. |
| `out/social-preview.png` | 1280×640 GitHub repo card. Upload under Settings → Social preview. |
| `out/check.html` | Renders every deliverable at the sizes it ships at, on both grounds. |

The wordmark is Sora 700, **converted to outlines**. Nothing here depends on
the font being installed.

The menu bar glyph is not one of these files: it is drawn in Swift by
`Sources/BeadsStatusBar/BeadleMark.swift` as a template image, so macOS tints
and inverts it like any other status item. Its geometry mirrors `export.py`; if
you change one, change the other.

## Regenerating

`export.py` needs `fonttools` and `brotli` to convert the wordmark to outlines,
and headless Chrome to rasterise:

```sh
python3 -m venv .venv && .venv/bin/pip install fonttools brotli
.venv/bin/python design/export.py
```

## How the mark was arrived at

Seven generations, each narrowing one variable, reviewed on a contact sheet
that renders every candidate at 128, 64, 32, 28, 24, 20 and 16px on dark, light
and mid grounds. `gen1.py` through `gen7.py` still generate their rounds, and
`marks/archive/` holds every candidate that was cut.

| Gen | Narrowed | Outcome |
| --- | --- | --- |
| 1 | Silhouette, monochrome | Strand, cluster, iris, graph, abacus, monogram. Cluster — the `circle.hexagongrid.fill` the app shipped with — turned to mush by 20px. |
| 2 | Silhouette again | Both surviving families converged on a ring of beads with an open centre: the hole is what stays distinct once the beads merge. |
| 3 | Bead form → hexagon | Hexagons tessellate, so the ring became a real honeycomb. The solid hexagon with punched beads read best at 16px. |
| 4 | Geometry | Bead count, hole size, wall weight, pointy-top vs flat-top. Beads belong on the edge midpoints; on the vertices the mark reads as a rotated triangle. |
| 5 | Colour | Eight hues, one treatment. Amber and coral were out on meaning alone — the app uses those for priority and failure. |
| 6 | Typography | Sora, against Inter, Space Grotesk, IBM Plex Sans and Plus Jakarta Sans. Geometric and squared, so it agrees with the hexagon. |
| 7 | Orientation | Flat-top shell with beads turned against it, drawn fat so the beads carry the mark. |

To review a round again:

```sh
python3 gen7.py
python3 ~/.claude/skills/logo-exploration/scripts/contact_sheet.py \
    --dir marks --name Beadle --fonts marks/fonts --title "Gen 7" --group
python3 -m http.server -d marks 8137
```
