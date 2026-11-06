"""v10: deep-waist violin + chin rest on the lower-left bout, upright vs tilted.

The remaining failure mode is symmetry: every candidate so far is mirror-symmetric
top to bottom of a narrow neck onto a bulbous body - which is a bottle. A violin
has a chin rest clamped to the lower-left bout, and that single asymmetry is
both violin-specific and cheap (a peninsula on the body edge, 5 dots).
"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from shapely import affinity
from shapely.geometry import Polygon

sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")
from svg_pipeline import spectrum, validate  # noqa: E402

HALF = [
    (50.0, 2.2), (53.6, 2.8), (55.2, 6.0), (54.0, 9.4), (52.8, 10.4),
    (52.8, 15.0), (52.4, 36.6), (54.0, 38.6), (59.0, 39.4), (63.4, 42.0),
    (64.6, 45.6), (62.6, 49.2), (59.0, 52.8), (59.8, 56.6), (63.6, 59.2),
    (67.0, 62.6), (68.2, 68.0), (67.6, 74.0), (65.4, 80.5), (61.8, 87.0),
    (57.6, 92.8), (53.4, 96.6), (50.0, 97.8),
]
CHIN = [(28.6, 73.0), (26.6, 69.0), (28.8, 65.2), (31.4, 67.4)]

half = [list(p) for p in HALF]
full = half + [[100.0 - x, y] for x, y in reversed(half[1:-1])]
i = min(range(len(full)), key=lambda k: (full[k][0] - 32.4) ** 2 + (full[k][1] - 74.0) ** 2)
withchin = full[:i + 1] + [list(p) for p in CHIN] + full[i + 1:]

cands = {"no chin rest": full, "chin rest": withchin}


def tilt(pts, ang):
    poly = affinity.rotate(Polygon(pts), ang, origin=(50, 60))
    ring = list(poly.exterior.coords)[:-1]
    # re-centre into the 0..100 box
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    dx = 50 - (min(xs) + max(xs)) / 2
    dy = 53 - (min(ys) + max(ys)) / 2
    return [[round(x + dx, 2), round(y + dy, 2)] for x, y in ring]


cands["chin rest, tilt-15"] = tilt(withchin, -15)

for name, dots in cands.items():
    issues, gap = validate(dots)
    ranked, ratio, share = spectrum(dots)
    print(f"{name:18s} n={len(dots):3d} gap={gap:5.2f} issues={len(issues) if issues else 0} "
          f"share={share*100:5.1f}% c4:c5={ratio:4.2f} k={[k for _, k in ranked[:4]]}")
    if issues:
        print("   ", issues[:3])

fig = plt.figure(figsize=(10.2, 3.7), dpi=100)
for i, (name, dots) in enumerate(cands.items()):
    ax = fig.add_axes([i * 0.333, 0.02, 0.32, 0.92])
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
fig.savefig("v10-chinrest.png")
print("wrote v10-chinrest.png")
json.dump(withchin, open("violin-chin-dots.json", "w"))
json.dump(cands["chin rest, tilt-15"], open("violin-chin-tilt-dots.json", "w"))
