"""Violin + snowman v2, judged at true toy scale.

Violin v1 problem: the MDI contour carries the neck at a slant, so the left wall
runs y 8->37 while the right wall only runs 5->17. The "stem" is half a stem,
and the body is 79 units tall against 13 of neck+scroll. Rebuilt as a mirrored
half with real violin proportions: body 61, neck 16, scroll 13 (a violin is
body 35.5cm : neck 13 : scroll 10.5).

Snowman v1 problem: arms span x 4 -> 96, i.e. 92 units against a 46-unit body,
with four prongs each. Shrunk about the shoulder, interior prong points only -
the ball points at each end of the arm run must not move, or the outline gets
gouged.
"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")
from svg_pipeline import spectrum, validate  # noqa: E402

VIOLIN = "/opt/workspace/projects/fourier/drafts/archives/20261030-0401-violin/violin-dots.json"
SNOWMAN = "/opt/workspace/projects/fourier/drafts/20261030-0602-snowman/snowman-dots.json"

# violin v2: right half, top-down, mirrored about x=50
V_HALF = [
    (50.0, 2.2), (53.4, 2.8), (55.6, 5.0), (55.2, 8.4), (52.6, 10.2),
    (53.4, 11.4), (53.4, 15.6), (52.9, 16.6), (52.9, 35.2), (55.0, 36.8),
    (61.0, 37.6), (67.5, 40.2), (70.0, 45.0), (65.8, 54.0), (63.2, 58.0),
    (64.2, 62.0), (68.0, 66.0), (71.5, 71.0), (73.0, 78.0), (71.8, 85.0),
    (67.5, 91.0), (60.5, 95.2), (53.0, 97.2), (50.0, 97.4),
]

# snowman v1: arm interior point ranges (endpoints are ball points, left alone)
LEFT_ARM = list(range(10, 20))   # (17.3,35.0) .. (21.44,26.65)
RIGHT_ARM = list(range(31, 41))


def mirror(half):
    return [list(p) for p in half] + [[100.0 - x, y] for x, y in reversed(half[1:-1])]


def shrink_arms(pts, s=0.55):
    ax, ay = 34.74, 34.68
    out = [list(p) for p in pts]
    for idx, (bx, by) in ((LEFT_ARM, (ax, ay)), (RIGHT_ARM, (100 - ax, ay))):
        for i in idx:
            x, y = pts[i]
            out[i] = [bx + (x - bx) * s, by + (y - by) * s]
    return out


def toy_axes(ax, dots, title):
    ax.plot([p[0] for p in dots] + [dots[0][0]], [p[1] for p in dots] + [dots[0][1]],
            ls=(0, (3, 2.6)), lw=2, color="black", solid_capstyle="round")
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    for sp in ax.spines.values():
        sp.set_visible(False)
    ax.set_title(f"{title}\nn={len(dots)}", fontsize=9)


violin_old = json.load(open(VIOLIN))
snow_old = json.load(open(SNOWMAN))
violin_new = mirror(V_HALF)
snow_new = shrink_arms(snow_old, s=0.55)

for name, dots in (("violin v1", violin_old), ("violin v2", violin_new),
                   ("snowman v1", snow_old), ("snowman v2", snow_new)):
    issues, gap = validate(dots)
    ranked, ratio, share = spectrum(dots)
    ks = [k for _, k in ranked[:4]]
    n_iss = len(issues) if issues else 0
    print(f"{name:12s} n={len(dots):3d} gap={gap:5.2f} issues={n_iss} "
          f"share={share*100:5.1f}% c4:c5={ratio:4.2f} k={ks}")
    if issues:
        print("   ", issues[:3])

fig, axes = plt.subplots(2, 2, figsize=(7.0, 7.0), dpi=100)
for ax, dots, title in zip(axes.ravel(),
                           (violin_old, violin_new, snow_old, snow_new),
                           ("violin v1 (draft 41)", "violin v2 long neck",
                            "snowman v1 (draft 42)", "snowman v2 small arms")):
    toy_axes(ax, dots, title)
fig.tight_layout()
fig.savefig("violin-snowman-v2.png")
print("wrote violin-snowman-v2.png")

json.dump(violin_new, open("violin-v2-dots.json", "w"))
json.dump(snow_new, open("snowman-v2-dots.json", "w"))
print("wrote violin-v2-dots.json, snowman-v2-dots.json")
