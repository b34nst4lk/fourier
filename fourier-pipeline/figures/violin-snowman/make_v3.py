"""Violin v3: correct violin proportions + a scroll curl, with a toy-scale panel.

v2 read as a guitar because its body was 46 wide x 61 tall = 1.33:1. A violin
body is 35.5 long x 20.5 wide = 1.73:1, upper bout 0.76 of the lower, waist 0.60
of the lower. At 1.33:1 the silhouette is a guitar no matter what the neck does.
"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")
from svg_pipeline import spectrum, validate  # noqa: E402

# y 2..97.6 = 95.6 tall. scroll 18 (19%), neck 18 (19%), body 60 (62%).
# body: 36 wide (1.67:1), upper bout 27.2 (0.76), waist 21.6 (0.60).
V_HALF = [
    (50.0, 2.0), (54.0, 2.6), (55.6, 5.6), (54.6, 8.8), (51.6, 10.2),
    (53.2, 11.2), (53.2, 15.0), (52.8, 15.8), (52.8, 37.0), (54.2, 39.2),
    (58.0, 40.0), (62.4, 42.6), (63.6, 46.0), (63.0, 50.5), (60.9, 53.5),
    (60.8, 56.5), (62.4, 59.0), (65.4, 62.0), (67.4, 67.0), (67.8, 73.0),
    (67.0, 79.0), (64.4, 86.0), (59.6, 92.0), (54.4, 96.4), (50.0, 97.6),
]


def mirror(half):
    return [list(p) for p in half] + [[100.0 - x, y] for x, y in reversed(half[1:-1])]


def draw(ax, dots, lw=2):
    ax.plot([p[0] for p in dots] + [dots[0][0]], [p[1] for p in dots] + [dots[0][1]],
            ls=(0, (3, 2.6)), lw=lw, color="black", solid_capstyle="round")
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    for sp in ax.spines.values():
        sp.set_visible(False)


v3 = mirror(V_HALF)
issues, gap = validate(v3)
ranked, ratio, share = spectrum(v3)
print(f"violin v3  n={len(v3)} gap={gap:.2f} issues={len(issues) if issues else 0} "
      f"share={share*100:.1f}% c4:c5={ratio:.2f} k={[k for _, k in ranked[:4]]}")
if issues:
    print(issues[:3])

fig = plt.figure(figsize=(3.4, 3.4), dpi=100)          # 340 px = toy scale
ax = fig.add_axes([0, 0, 1, 1])
draw(ax, v3, lw=2)
fig.savefig("violin-v3-toy.png")
fig2 = plt.figure(figsize=(7.0, 7.0), dpi=100)
ax2 = fig2.add_axes([0, 0, 1, 1])
draw(ax2, v3, lw=3)
fig2.savefig("violin-v3-zoom.png")
print("wrote violin-v3-toy.png, violin-v3-zoom.png")
json.dump(v3, open("violin-v3-dots.json", "w"))
