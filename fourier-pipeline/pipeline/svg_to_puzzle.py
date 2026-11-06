#!/usr/bin/env python3
"""SVG silhouette -> toy puzzle polygon.

The store's "target" trace is a 512-pt arc-length resample of the closed
polygon through the dots, so what the player sees is exactly the straight-edge
polygon: IoU against the source silhouette is an honest fidelity score.

Prints the IoU-vs-dot-count curve so the dot budget is chosen from data.
Usage: python svg_to_puzzle.py duck [--max-dots 30] [--margin 4] [--dump out.json]
"""
import argparse, json, math
import numpy as np
import shapely.geometry as sg
from svgpathtools import svg2paths2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def flatten(svg_path, n=400):
    paths, _, _ = svg2paths2(svg_path)
    subs = []
    for p in paths:
        for sub in p.continuous_subpaths():
            pts = [sub.point(t / n) for t in range(n + 1)]
            xy = np.array([[z.real, z.imag] for z in pts])
            if len(xy) >= 3:
                subs.append(xy)
    return subs


def normalise(xy, margin=4.0):
    """Preserve aspect ratio, centre, map into [margin, 100-margin]; y-down kept."""
    lo, hi = xy.min(axis=0), xy.max(axis=0)
    span = hi - lo
    scale = (100.0 - 2 * margin) / max(span[0], span[1])
    out = (xy - lo) * scale
    off = ((100.0 - 2 * margin) - (span * scale)) / 2.0
    return out + off + margin


def _rdp(points, eps):
    if len(points) < 3:
        return points
    a, b = points[0], points[-1]
    ab = b - a
    nrm = np.hypot(*ab)
    if nrm == 0:
        d = np.hypot(*(points - a).T)
    else:
        rel = points - a
        d = np.abs(ab[0] * rel[:, 1] - ab[1] * rel[:, 0]) / nrm
    i = int(np.argmax(d))
    if d[i] > eps:
        return np.vstack([_rdp(points[: i + 1], eps)[:-1], _rdp(points[i:], eps)])
    return np.array([a, b])


def rdp_closed(xy, eps):
    pts = xy[:-1] if np.allclose(xy[0], xy[-1]) else xy
    i1 = int(np.argmax(np.hypot(*(pts - pts[0]).T)))
    a = _rdp(pts[: i1 + 1], eps)
    b = _rdp(np.vstack([pts[i1:], pts[:1]]), eps)
    return np.vstack([a[:-1], b[:-1]])


def at_count(xy, target, lo=0.05, hi=25.0):
    best = None
    for _ in range(45):
        mid = (lo + hi) / 2
        out = rdp_closed(xy, mid)
        if best is None or abs(len(out) - target) < abs(len(best[1]) - target):
            best = (mid, out)
        if len(out) == target:
            break
        lo, hi = (mid, hi) if len(out) > target else (lo, mid)
    return best[1]


def seg_int(p1, p2, p3, p4):
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])
    def on(a, b, c):
        return (min(a[0], b[0]) <= c[0] <= max(a[0], b[0])
                and min(a[1], b[1]) <= c[1] <= max(a[1], b[1]))
    d1, d2 = ccw(p3, p4, p1), ccw(p3, p4, p2)
    d3, d4 = ccw(p1, p2, p3), ccw(p1, p2, p4)
    if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
        return True
    return ((d1 == 0 and on(p3, p4, p1)) or (d2 == 0 and on(p3, p4, p2))
            or (d3 == 0 and on(p1, p2, p3)) or (d4 == 0 and on(p1, p2, p4)))


def validate(dots):
    errs, n = [], len(dots)
    if n < 3:
        errs.append("too few dots")
    if not 12 <= n <= 30:
        errs.append(f"dot count {n} outside 12-30")
    if any(not (0 <= x <= 100 and 0 <= y <= 100) for x, y in dots):
        errs.append("dot out of bounds")
    md = min(math.dist(dots[i], dots[(i + 1) % n]) for i in range(n))
    if md < 0.5:
        errs.append(f"min adjacent dist {md:.2f} < 0.5")
    inter = [(i, j) for i in range(n) for j in range(i + 1, n)
             if not (j == i + 1 or (i == 0 and j == n - 1))
             and seg_int(dots[i], dots[(i + 1) % n], dots[j], dots[(j + 1) % n])]
    if inter:
        errs.append(f"self-intersections {inter}")
    return errs, md


def iou(dots, source_poly):
    cand = sg.Polygon(dots)
    if not cand.is_valid:
        return 0.0
    u = cand.union(source_poly).area
    return cand.intersection(source_poly).area / u if u else 0.0


def curve(name, max_dots=30, margin=4.0):
    subs = flatten(f"svg/{name}.svg")
    subs.sort(key=lambda a: -abs(sg.Polygon(a).area))
    outer = normalise(subs[0], margin)
    src = sg.Polygon(outer)
    rows = []
    for target in range(12, max_dots + 1):
        arr = at_count(outer, target)
        dots = [[round(float(x), 2), round(float(y), 2)] for x, y in arr]
        errs, md = validate(dots)
        rows.append({"n": len(dots), "iou": iou(dots, src), "min_adj": md,
                     "ok": not errs, "errs": errs, "dots": dots})
    return outer, src, rows


def sheet(name, outer, rows, picks, path="compare.png"):
    fig, axes = plt.subplots(1, len(picks) + 1, figsize=(3.2 * (len(picks) + 1), 3.6))
    axes = np.atleast_1d(axes)
    axes[0].fill(outer[:, 0], outer[:, 1], color="0.75", lw=0)
    axes[0].set_title(f"source {name}", fontsize=9)
    for ax, r in zip(axes[1:], picks):
        d = np.array(r["dots"] + [r["dots"][0]])
        ax.fill(outer[:, 0], outer[:, 1], color="0.88", lw=0)
        ax.plot(d[:, 0], d[:, 1], "-", color="black", lw=1.2)
        ax.plot(d[:-1, 0], d[:-1, 1], "o", color="tab:red", ms=3)
        ax.set_title(f"n={r['n']}  IoU={r['iou']:.3f}", fontsize=9)
    for ax in axes:
        ax.set_aspect("equal"); ax.invert_yaxis(); ax.axis("off")
    plt.tight_layout(); plt.savefig(path, dpi=110); plt.close()
    return path


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--max-dots", type=int, default=30)
    ap.add_argument("--margin", type=float, default=4.0)
    a = ap.parse_args()
    outer, src, rows = curve(a.name, a.max_dots, a.margin)
    print(f"{'n':>3} {'IoU':>6} {'min_adj':>8}  ok")
    for r in rows:
        print(f"{r['n']:>3} {r['iou']:>6.3f} {r['min_adj']:>8.2f}  {r['ok']}"
              + ("" if r["ok"] else f"  {r['errs']}"))
    ok = [r for r in rows if r["ok"]]
    top = max(r["iou"] for r in ok)
    picks = sorted(sorted(ok, key=lambda r: -r["iou"])[:1]
                   + [min(ok, key=lambda r: abs(r["iou"] - top * 0.97))]
                   + [ok[0]], key=lambda r: r["n"])
    dedup, seen = [], set()
    for p in picks:
        if p["n"] not in seen:
            dedup.append(p); seen.add(p["n"])
    sheet(a.name, outer, rows, dedup, f"compare-{a.name}.png")
    print(f"\nbest n={max(ok, key=lambda r: r['iou'])['n']} IoU={top:.3f}; wrote compare-{a.name}.png")
    for p in dedup:
        print(f"pick n={p['n']} iou={p['iou']:.3f}: {json.dumps(p['dots'])}")
