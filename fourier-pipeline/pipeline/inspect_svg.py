#!/usr/bin/env python3
"""Inspect candidate SVG silhouettes: subpath count, contour sizes, and a contact sheet."""
import sys, pathlib, glob
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from svgpathtools import svg2paths2
import shapely.geometry as sg

def contours(svg_path):
    paths, attrs, svg_attrs = svg2paths2(svg_path)
    out = []
    for p in paths:
        for sub in p.continuous_subpaths():
            pts = [sub.point(t / 200.0) for t in range(201)]
            xy = np.array([[z.real, z.imag] for z in pts])
            if len(xy) < 3:
                continue
            poly = sg.Polygon(xy)
            out.append({"xy": xy, "area": abs(poly.area), "poly": poly})
    out.sort(key=lambda d: -d["area"])
    return out

def load(name):
    return contours(f"svg/{name}.svg")

if __name__ == "__main__":
    names = sorted(pathlib.Path(p).stem for p in glob.glob("svg/*.svg"))
    names = [n for n in names if pathlib.Path(f"svg/{n}.svg").stat().st_size > 60]
    print(f"{'icon':<10} subpaths  largest-area  areas")
    keep = []
    for n in names:
        cs = load(n)
        areas = [round(c["area"], 1) for c in cs]
        print(f"{n:<10} {len(cs):<9} {areas[:1]}  {areas}")
        keep.append((n, cs))

    cols = 5
    rows = (len(keep) + cols - 1) // cols
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 2.4, rows * 2.6))
    axes = np.atleast_2d(axes)
    for i, (n, cs) in enumerate(keep):
        ax = axes[i // cols][i % cols]
        for c in cs:
            xy = c["xy"]
            ax.fill(xy[:, 0], xy[:, 1], color="black", lw=0)
        ax.set_title(f"{n} ({len(cs)})", fontsize=9)
        ax.set_aspect("equal"); ax.invert_yaxis(); ax.axis("off")
    for j in range(len(keep), rows * cols):
        axes[j // cols][j % cols].axis("off")
    plt.tight_layout()
    plt.savefig("contact.png", dpi=110)
    print("\nwrote contact.png")
