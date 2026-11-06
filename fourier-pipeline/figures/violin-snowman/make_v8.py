"""v8: violin with a bow crossing it, as a computed union polygon.

A bare violin outline is a bottle - the source MDI icon's own silhouette reads
the same way. What makes clip-art read as a violin is the bow lying across the
body. Two overlapping shapes cannot both be traced by one closed loop, but the
UNION of them is a simple polygon: the loop follows the violin's edge until it
meets the bow, runs out along the bow, and rejoins. shapely does that, then RDP
brings the ring back under the 50-dot ceiling.
"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from shapely import affinity
from shapely.geometry import Polygon
from shapely.ops import unary_union

sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")
from svg_pipeline import spectrum, validate  # noqa: E402

HALF = [
    (50.0, 2.2), (53.6, 2.8), (55.2, 6.0), (54.0, 9.4), (52.8, 10.4),
    (52.8, 15.0), (52.4, 36.6), (54.0, 38.6), (59.0, 39.4), (63.4, 42.0),
    (64.6, 45.6), (62.9, 49.0), (60.9, 53.0), (61.4, 56.6), (63.6, 59.2),
    (67.0, 62.6), (68.2, 68.0), (67.6, 74.0), (65.4, 80.5), (61.8, 87.0),
    (57.6, 92.8), (53.4, 96.6), (50.0, 97.8),
]


def mirror(half):
    return half + [(100.0 - x, y) for x, y in reversed(half[1:-1])]


def rdp(pts, eps):
    pts = np.asarray(pts, float)
    if len(pts) < 3:
        return pts
    keep = np.zeros(len(pts), bool)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        i0, i1 = stack.pop()
        if i1 - i0 < 2:
            continue
        a, b = pts[i0], pts[i1]
        seg = b - a
        L = np.hypot(*seg) or 1e-9
        d = np.abs(seg[0] * (pts[i0 + 1:i1, 1] - a[1])
                   - seg[1] * (pts[i0 + 1:i1, 0] - a[0])) / L
        j = int(np.argmax(d))
        if d[j] > eps:
            k = i0 + 1 + j
            keep[k] = True
            stack += [(i0, k), (k, i1)]
    return pts[keep]


def ring_to_dots(ring, max_n=50):
    pts = np.asarray(ring)[:-1]          # drop duplicated closing vertex
    far = int(np.argmax(((pts - pts[0]) ** 2).sum(1)))
    arc_a = pts[:far + 1]
    arc_b = np.vstack([pts[far:], pts[:1]])
    for eps in np.arange(0.4, 8.0, 0.2):
        a = rdp(arc_a, eps)
        b = rdp(arc_b, eps)
        simp = np.vstack([a[:-1], b[:-1]])
        if len(simp) <= max_n:
            return [[round(float(x), 2), round(float(y), 2)] for x, y in simp], eps
    return None, None


body = Polygon(mirror(HALF))
bow = affinity.rotate(Polygon([(-23, -2.4), (23, -2.4), (23, 2.4), (-23, 2.4)]), 38)
bow = affinity.translate(bow, 60.5, 62.5)          # crosses the lower bout, out both ends

variants = {"A upright+bow": body}
for ang in (-18, -28):
    variants[f"B tilt{ang}+bow"] = affinity.rotate(body, ang, origin=(50, 60))

panels = []
for name, viol in variants.items():
    u = unary_union([viol, bow])
    dots, eps = ring_to_dots(u.exterior.coords)
    issues, gap = validate(dots)
    ranked, ratio, share = spectrum(dots)
    print(f"{name:16s} n={len(dots):3d} eps={eps:.1f} gap={gap:5.2f} "
          f"issues={len(issues) if issues else 0} share={share*100:5.1f}% "
          f"c4:c5={ratio:4.2f} k={[k for _, k in ranked[:4]]}")
    if issues:
        print("   ", issues[:3])
    panels.append((name, dots))

# reference: the shipped icon's own filled silhouette
ref = json.load(open("/opt/workspace/projects/fourier/drafts/archives/20261030-0401-violin/violin-dots.json"))
panels.insert(0, ("draft 41 (source icon)", ref))

fig = plt.figure(figsize=(13.6, 3.7), dpi=100)
for i, (name, dots) in enumerate(panels):
    ax = fig.add_axes([i * 0.25, 0.02, 0.24, 0.92])
    ax.plot([p[0] for p in dots] + [dots[0][0]], [p[1] for p in dots] + [dots[0][1]],
            ls=(0, (3, 2.6)), lw=2, color="black", solid_capstyle="round")
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    for sp in ax.spines.values():
        sp.set_visible(False)
    ax.set_title(f"{name}  n={len(dots)}", fontsize=9)
fig.savefig("v8-union.png")
print("wrote v8-union.png")
for name, dots in panels[1:]:
    json.dump(dots, open(f"violin-{name.split()[0].lower()}-dots.json", "w"))
