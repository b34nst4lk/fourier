"""v7: violin + bow (inserted once, not mirrored), snowman arms designed explicitly.

Fixes over v6: build() mirrored the bow onto the left side (n=54), and the
2-prong variant dropped the wrong right-arm indices because the icon's right arm
is not an exact mirror of its left. Arms are now authored for the left side and
reflected by construction, so prongs and reach are under control.
"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")
from svg_pipeline import spectrum, validate  # noqa: E402

HALF = [
    (50.0, 2.2), (53.6, 2.8), (55.2, 6.0), (54.0, 9.4), (52.8, 10.4),
    (52.8, 15.0), (52.4, 36.6), (54.0, 38.6), (59.0, 39.4), (63.4, 42.0),
    (64.6, 45.6), (62.9, 49.0), (60.9, 53.0), (61.4, 56.6), (63.6, 59.2),
    (67.0, 62.6), (68.2, 68.0), (67.6, 74.0), (65.4, 80.5), (61.8, 87.0),
    (57.6, 92.8), (53.4, 96.6), (50.0, 97.8),
]
BOW = [(59.5, 3.0), (85.0, 76.0), (85.5, 81.5), (82.0, 80.5), (57.5, 8.0)]

ARM = [  # left arm, ball point (31.7,43.64) -> ball point (34.8,34.63)
    (26.0, 40.5), (19.5, 41.0), (16.5, 37.0), (22.0, 33.5),
    (18.0, 29.0), (21.0, 28.0), (25.0, 32.0), (23.5, 22.0),
    (27.0, 23.0), (31.0, 31.5),
]


def mirror_list(pts):
    return [list(p) for p in pts] + [[100.0 - x, y] for x, y in reversed(pts[1:-1])]


violin_plain = mirror_list(HALF)
violin_bow = violin_plain[:4] + [list(p) for p in BOW] + violin_plain[4:]

snow1 = json.load(open("/opt/workspace/projects/fourier/drafts/20261030-0602-snowman/snowman-dots.json"))
AX, AY = 34.74, 34.68
snow_v2 = [list(p) for p in snow1]
for i in list(range(10, 20)):
    x, y = snow1[i]
    snow_v2[i] = [AX + (x - AX) * 0.55, AY + (y - AY) * 0.55]
for i in list(range(31, 41)):
    x, y = snow1[i]
    snow_v2[i] = [(100 - AX) + (x - (100 - AX)) * 0.55, AY + (y - AY) * 0.55]

snow_v3 = (snow1[:10] + [list(p) for p in ARM]
           + snow1[20:31] + [[100.0 - x, y] for x, y in reversed(ARM)]
           + snow1[41:])

panels = [("violin + bow", violin_bow), ("violin plain", violin_plain),
          ("snowman 4 prongs", snow_v2), ("snowman 2 prongs", snow_v3)]
for name, dots in panels:
    issues, gap = validate(dots)
    ranked, ratio, share = spectrum(dots)
    print(f"{name:18s} n={len(dots):3d} gap={gap:5.2f} issues={len(issues) if issues else 0} "
          f"share={share*100:5.1f}% c4:c5={ratio:4.2f} k={[k for _, k in ranked[:4]]}")
    if issues:
        print("   ", issues[:3])

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
fig.savefig("v7-bakeoff.png")
print("wrote v7-bakeoff.png")
json.dump(violin_bow, open("violin-bow-dots.json", "w"))
json.dump(snow_v3, open("snowman-v3-dots.json", "w"))
