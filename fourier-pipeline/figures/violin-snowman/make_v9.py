"""v9: last violin bake-off. Baseline (long neck), deep C-bout, tapered neck, bow crossing.

Everything is measured against the one defect Jack named - the stem - plus the
likeness complaint. Four levers, all cheap, all at 340 px.
"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from shapely import affinity
from shapely.geometry import Polygon
from shapely.ops import unary_union

sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")
from svg_pipeline import spectrum, validate  # noqa: E402
from make_v8 import ring_to_dots  # noqa: E402  (reuse RDP ring simplifier)

BASE = [
    (50.0, 2.2), (53.6, 2.8), (55.2, 6.0), (54.0, 9.4), (52.8, 10.4),
    (52.8, 15.0), (52.4, 36.6), (54.0, 38.6), (59.0, 39.4), (63.4, 42.0),
    (64.6, 45.6), (62.9, 49.0), (60.9, 53.0), (61.4, 56.6), (63.6, 59.2),
    (67.0, 62.6), (68.2, 68.0), (67.6, 74.0), (65.4, 80.5), (61.8, 87.0),
    (57.6, 92.8), (53.4, 96.6), (50.0, 97.8),
]


def mirror(half):
    return [list(p) for p in half] + [[100.0 - x, y] for x, y in reversed(half[1:-1])]


def variant(**kw):
    h = [list(p) for p in BASE]
    if kw.get("waist"):
        h[11], h[12], h[13] = (62.6, 49.2), (59.0, 52.8), (59.8, 56.6)
    if kw.get("taper"):
        h[1], h[2], h[3] = (54.2, 2.6), (56.0, 6.0), (54.6, 9.6)
        h[4], h[5], h[6] = (53.2, 10.0), (53.0, 15.0), (51.9, 36.6)
    return mirror(h)


cands = {
    "1 baseline": variant(),
    "2 deep waist": variant(waist=True),
    "3 taper+waist": variant(waist=True, taper=True),
}

body = Polygon(variant(waist=True))
bow = affinity.rotate(Polygon([(-40, -2.1), (40, -2.1), (40, 2.1), (-40, 2.1)]), 32)
bow = affinity.translate(bow, 52, 55)
u = unary_union([body, bow])
dots, eps = ring_to_dots(u.exterior.coords)
cands["4 bow crossing"] = dots

for name, dots in cands.items():
    issues, gap = validate(dots)
    ranked, ratio, share = spectrum(dots)
    print(f"{name:16s} n={len(dots):3d} gap={gap:5.2f} issues={len(issues) if issues else 0} "
          f"share={share*100:5.1f}% c4:c5={ratio:4.2f} k={[k for _, k in ranked[:4]]}")
    if issues:
        print("   ", issues[:3])

fig = plt.figure(figsize=(13.6, 3.7), dpi=100)
for i, (name, dots) in enumerate(cands.items()):
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
fig.savefig("v9-bakeoff.png")
print("wrote v9-bakeoff.png")
json.dump(cands["3 taper+waist"], open("violin-v9-dots.json", "w"))
