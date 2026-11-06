"""V6: violin with a long neck and a bow; snowman arm simplification.

Draft 41's geometry: the violin neck only spans y 2->17 (15 units of 96), and
dots 2-11 are a separate closed excursion alongside it - the MDI icon's bow,
which at 340 px reads as a stray finger on a snowman.

A bow is a peninsula, not a hole: the outline leaves the pegbox, runs out and
back, and rejoins the next dot. Same topology as the snowman's arms, so no new
validator problem. It also carries the recognition, because a bowed instrument
is unambiguous in a way a bare body is not.
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


def build(half, bow_at=None, bow=None):
    pts = [list(p) for p in half]
    if bow and bow_at is not None:
        pts = pts[:bow_at] + [list(p) for p in bow] + pts[bow_at:]
    return pts + [[100.0 - x, y] for x, y in reversed(pts[1:-1])]


def shrink(pts, idx, s, cx, cy):
    out = [list(p) for p in pts]
    for i in idx:
        x, y = pts[i]
        out[i] = [cx + (x - cx) * s, cy + (y - cy) * s]
    return out


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


violin_bow = build(HALF, bow_at=4, bow=BOW)
violin_plain = build(HALF)

snow1 = json.load(open("/opt/workspace/projects/fourier/drafts/20261030-0602-snowman/snowman-dots.json"))
AX, AY = 34.74, 34.68
snow_v2 = shrink(snow1, list(range(10, 20)) + list(range(31, 41)), 0.55, AX, AY)
# also scale about the mirrored shoulder for the right arm
for i in range(31, 41):
    x, y = snow1[i]
    snow_v2[i] = [100 - AX + (x - (100 - AX)) * 0.55, AY + (y - AY) * 0.55]
# two prongs per arm: drop the (5.42,25.35)-(7.71,21.64)-(16.46,26.72) triplet
keep = [i for i in list(range(10, 20)) + list(range(31, 41))
        if i not in (14, 15, 16, 35, 36, 37)]
snow_v3 = shrink(snow1, keep, 0.62, AX, AY)
for i in [31, 32, 33, 34, 38, 39, 40]:
    x, y = snow1[i]
    snow_v3[i] = [100 - AX + (x - (100 - AX)) * 0.62, AY + (y - AY) * 0.62]

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
    draw(ax, dots)
    ax.set_title(f"{name}  n={len(dots)}", fontsize=9)
fig.savefig("v6-bakeoff.png")
print("wrote v6-bakeoff.png")
json.dump(violin_bow, open("violin-bow-dots.json", "w"))
json.dump(snow_v3, open("snowman-v3-dots.json", "w"))
