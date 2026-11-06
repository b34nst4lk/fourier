#!/usr/bin/env python3
"""Numbered review preview for a Fourier-toy draft.

Left  : the shape exactly as the toy draws it (340 px, dashed, unfilled, lw 1.6).
Right : same polygon, enlarged, every node numbered 1..n with a leader line.
Table : node -> (x, y) written next to the image and printed to stdout.

Usage: numbered_preview.py DOTS.json -o OUT.png --name label [--table]
"""
import argparse
import json

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

INK = "#1b1a17"
ACC = "#c0392b"


def load(path):
    d = json.load(open(path))
    P = d["dots"] if isinstance(d, dict) else d
    return np.asarray(P, dtype=float)


def toy_panel(ax, P, title):
    xs = np.append(P[:, 0], P[0, 0])
    ys = np.append(P[:, 1], P[0, 1])
    ax.plot(xs, ys, color=INK, lw=1.152, ls=(0, (2.16, 1.87)))
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    for s in ax.spines.values():
        s.set_visible(False)
    ax.set_title(title, fontsize=7, color="#555")


def relax(fig, ax, texts, P, n_iter=900):
    """Pixel-space label packing with real bboxes + repulsion from the ink."""
    fig.canvas.draw()
    rend = fig.canvas.get_renderer()
    boxes = [t.get_window_extent(rend) for t in texts]
    w = np.array([b.width + 3 for b in boxes])
    h = np.array([b.height + 2 for b in boxes])
    xy = np.array([b.get_points().mean(axis=0) for b in boxes])
    anch = ax.transData.transform(P)
    seg_a, seg_b = P[:-1], P[1:]
    sa = ax.transData.transform(seg_a)
    sb = ax.transData.transform(seg_b)
    n = len(texts)
    for _ in range(n_iter):
        for i in range(n):
            for j in range(i + 1, n):
                dx = xy[j, 0] - xy[i, 0]
                dy = xy[j, 1] - xy[i, 1]
                ox = (w[i] + w[j]) / 2 + 3.0 - abs(dx)
                oy = (h[i] + h[j]) / 2 + 3.0 - abs(dy)
                if ox > 0 and oy > 0:
                    if ox < oy:
                        s = 1.0 if dx >= 0 else -1.0
                        xy[i, 0] -= s * ox / 2
                        xy[j, 0] += s * ox / 2
                    else:
                        s = 1.0 if dy >= 0 else -1.0
                        xy[i, 1] -= s * oy / 2
                        xy[j, 1] += s * oy / 2
        # keep labels off the ink
        for i in range(n):
            ab = sb - sa
            t = np.clip(((xy[i] - sa) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-9), 0, 1)
            proj = sa + ab * t[:, None]
            dv = xy[i] - proj
            dist = np.hypot(dv[:, 0], dv[:, 1])
            k = int(dist.argmin())
            need = h[i] / 2 + 2.5
            if dist[k] < need:
                u = dv[k] / (dist[k] or 1e-6)
                xy[i] += u * (need - dist[k])
        xy += 0.008 * (anch + np.array([0, 16]) - xy)
    for t, p in zip(texts, xy):
        d = ax.transData.inverted().transform(p)
        t.set_position(d)


def table_panel(fig, ax, P):
    ax.set_xlim(-4, 104)
    ax.set_ylim(104, -4)
    ax.set_aspect("equal")
    ax.axis("off")
    xs = np.append(P[:, 0], P[0, 0])
    ys = np.append(P[:, 1], P[0, 1])
    ax.plot(xs, ys, color=INK, lw=1.6, ls=(0, (2.6, 2.2)), zorder=1)
    ax.plot(P[:, 0], P[:, 1], "o", ms=2.0, color=ACC, zorder=3)
    texts = []
    for i, (x, y) in enumerate(P, start=1):
        texts.append(ax.text(x, y, str(i), fontsize=6.5, color=ACC,
                             ha="center", va="center", zorder=4,
                             bbox=dict(boxstyle="round,pad=0.12", fc="white",
                                       ec="none", alpha=0.9)))
    relax(fig, ax, texts, P)
    for t, (x, y) in zip(texts, P):
        lx, ly = t.get_position()
        if np.hypot(lx - x, ly - y) > 1.6:
            ax.plot([x, lx], [y, ly], color=ACC, lw=0.4, alpha=0.5, zorder=2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dots")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--name", default="draft")
    ap.add_argument("--table", action="store_true", help="write node table next to image")
    a = ap.parse_args()
    P = load(a.dots)
    fig = plt.figure(figsize=(14.0, 5.9), dpi=150)
    ax1 = fig.add_axes([0.02, 0.06, 0.235, 0.86])
    ax2 = fig.add_axes([0.30, 0.03, 0.68, 0.92])
    toy_panel(ax1, P, "toy scale: 340 px, dashed, no fill")
    table_panel(fig, ax2, P)
    fig.text(0.5, 0.965, f"{a.name}: n={len(P)} -- nodes numbered 1..{len(P)}",
             ha="center", fontsize=10, color="#333")
    fig.savefig(a.out, dpi=130, facecolor="white")
    if a.table:
        base = a.out.rsplit(".", 1)[0]
        with open(base + "-nodes.csv", "w") as f:
            f.write("node,x,y\n")
            for i, (x, y) in enumerate(P, start=1):
                f.write(f"{i},{x:.2f},{y:.2f}\n")
        for i, (x, y) in enumerate(P, start=1):
            print(f"{i:>3}  {x:6.2f}  {y:6.2f}")
    print(f"wrote {a.out}")


if __name__ == "__main__":
    main()
