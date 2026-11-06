"""Violin bake-off at 340 px + snowman seam diagnostic.

A violin outline is not a smooth bottle: it has four corners where each C-bout
meets the bouts, and those kinks are what distinguishes it from a guitar or a
gourd. Dots are joined by straight dashed segments, so an angular kink survives
at toy scale while a smooth arc just looks like a bottle.
"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")
from svg_pipeline import spectrum, validate  # noqa: E402

# V3: smooth (shipped as the last render), 1.67:1
V3 = [(50.0, 2.0), (54.0, 2.6), (55.6, 5.6), (54.6, 8.8), (51.6, 10.2),
      (53.2, 11.2), (53.2, 15.0), (52.8, 15.8), (52.8, 37.0), (54.2, 39.2),
      (58.0, 40.0), (62.4, 42.6), (63.6, 46.0), (63.0, 50.5), (60.9, 53.5),
      (60.8, 56.5), (62.4, 59.0), (65.4, 62.0), (67.4, 67.0), (67.8, 73.0),
      (67.0, 79.0), (64.4, 86.0), (59.6, 92.0), (54.4, 96.4), (50.0, 97.6)]

# V4: four C-bout corners, 1.62:1 body (36 wide x 58.4 tall)
V4 = [(50.0, 2.0), (53.8, 2.6), (55.4, 5.4), (54.4, 8.4), (51.8, 9.8),
      (53.0, 10.8), (53.0, 14.6), (52.6, 15.4), (52.6, 37.2), (53.8, 39.0),
      (58.2, 39.8), (62.2, 42.0), (64.4, 45.4), (63.4, 48.2), (61.2, 50.4),
      (60.5, 53.4), (60.5, 56.6), (62.0, 59.2), (65.0, 60.8), (67.6, 64.0),
      (68.0, 67.5), (67.4, 72.0), (66.4, 77.5), (63.6, 84.0), (59.4, 90.2),
      (55.0, 95.0), (50.0, 97.6)]

# V5: same corners, wider body (1.45:1) - does width help or hurt the read?
V5 = [(50.0, 2.0), (53.8, 2.6), (55.4, 5.4), (54.4, 8.4), (51.8, 9.8),
      (53.0, 10.8), (53.0, 14.6), (52.6, 15.4), (52.6, 37.2), (53.8, 39.0),
      (59.0, 39.8), (64.0, 42.0), (66.8, 45.4), (65.6, 48.4), (62.6, 50.6),
      (61.6, 53.6), (61.6, 56.8), (63.4, 59.4), (67.0, 61.0), (70.2, 64.2),
      (70.8, 67.5), (70.0, 72.0), (68.8, 77.5), (65.4, 84.0), (60.4, 90.2),
      (55.4, 95.2), (50.0, 97.8)]


def mirror(half):
    return [list(p) for p in half] + [[100.0 - x, y] for x, y in reversed(half[1:-1])]


def draw(ax, dots, lw=2):
    ax.plot([p[0] for p in dots] + [dots[0][0]], [p[1] for p in dots] + [dots[0][1]],
            ls=(0, (3, 2.6)), lw=lw, color="black", solid_capstyle="round")
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    for sp in ax.spines.values():
        sp.set_visible(False)


snow = json.load(open("snowman-v2-dots.json"))

fig = plt.figure(figsize=(13.6, 3.7), dpi=100)
for i, (name, half) in enumerate((("V3 smooth", V3), ("V4 corners", V4), ("V5 corners wide", V5))):
    dots = mirror(half)
    issues, gap = validate(dots)
    ranked, ratio, share = spectrum(dots)
    print(f"{name:16s} n={len(dots)} gap={gap:.2f} issues={len(issues) if issues else 0} "
          f"share={share*100:.1f}% c4:c5={ratio:.2f} k={[k for _, k in ranked[:4]]}")
    if issues:
        print("   ", issues[:2])
    ax = fig.add_axes([i * 0.25, 0.02, 0.24, 0.92])
    draw(ax, dots)
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_title(name, fontsize=9)
    json.dump(dots, open(f"violin-{name.split()[0].lower()}-dots.json", "w"))

# snowman seam, magnified 3x around the left shoulder
ax = fig.add_axes([0.76, 0.02, 0.23, 0.92])
draw(ax, snow, lw=3)
ax.set_xlim(12, 48)
ax.set_ylim(54, 18)
ax.set_title("snowman v2 seam 3x", fontsize=9)
fig.savefig("violin-bakeoff.png")
print("wrote violin-bakeoff.png")
