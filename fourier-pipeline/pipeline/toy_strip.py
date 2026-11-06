#!/usr/bin/env python3
"""Render candidate dot sets as a strip of exact toy-scale panels.

Each panel is drawn as its own figure at figsize=(3.4, 3.4), dpi=100 with
add_axes([0, 0, 1, 1]) so the axes fills the figure: **exactly 340x340 px**,
the size the toy draws at (100 shape units ~= 340 px). Panels are pasted into
one image with PIL after rasterising, so nothing is resampled afterwards.

    python3 toy_strip.py v3-dots.json a-dots.json d-dots.json -o strip.png

Why one figure per panel: computing rect=[x0, y0, w, h] as figure fractions in
a single N-axes figure is where the "empty panel / wrong scale" bug comes from.
One figure per panel has no fractions to get wrong.

Judge variants here — dashed, unfilled, 340 px — never in a zoomed panel.
Panel order is printed so the strip can be read left to right.
"""
import argparse
import io
import json

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from PIL import Image  # noqa: E402

PANEL_IN = 3.4   # inches
DPI = 100        # -> 340 px per panel
PX = int(PANEL_IN * DPI)
DASH = (0, (3, 2.6))   # the toy's setLineDash([3, 2.6])


def panel(path, lw=1.6):
    dots = json.load(open(path))
    fig = plt.figure(figsize=(PANEL_IN, PANEL_IN), dpi=DPI)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)          # y down, as the toy draws
    ax.set_aspect("equal")
    ax.axis("off")
    ring = list(dots) + [dots[0]]
    ax.plot([p[0] for p in ring], [p[1] for p in ring],
            color="black", lw=lw, ls=DASH, solid_capstyle="butt")
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=DPI)
    plt.close(fig)
    buf.seek(0)
    im = Image.open(buf).convert("RGB")
    if im.size != (PX, PX):
        raise SystemExit(f"{path}: panel is {im.size}, expected {(PX, PX)}")
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dots", nargs="+", help="one -dots.json per panel")
    ap.add_argument("-o", "--out", default="strip.png")
    ap.add_argument("--gap", type=int, default=10, help="white gutter, px")
    a = ap.parse_args()
    panels = [panel(p) for p in a.dots]
    n = len(panels)
    w = n * PX + (n - 1) * a.gap
    strip = Image.new("RGB", (w, PX), "white")
    for i, im in enumerate(panels):
        strip.paste(im, (i * (PX + a.gap), 0))
    strip.save(a.out)
    print(f"{a.out} {strip.size[0]}x{strip.size[1]} px, {PX}px panels, left->right: "
          + " | ".join(a.dots))


if __name__ == "__main__":
    main()
