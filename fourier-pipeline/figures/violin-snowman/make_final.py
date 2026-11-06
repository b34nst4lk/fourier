"""Final violin + snowman: what actually changed, and why.

VIOLIN (draft 41 -> v2)
  Named defect: "the stem is too short". In draft 41 the neck runs y 2->17, i.e.
  15 units of a 96-unit figure (16%), and the bow beside it reads as a stray
  finger. v2: neck y 15->36.6, 21.6 units (23%), body 61 units at 1.63:1, waist
  deepened to half-width 9.0 so the C-bout reads.
  NOT fixed: a bare violin silhouette at 340 px still reads gourd/guitar. The
  distinguishing mark on a real violin is the f-hole pair, which is interior -
  unreachable without breaking the single-loop law, and every edge-cut pocket
  attempt reads as damage. Recorded rather than papered over.

SNOWMAN (draft 42 -> v2)
  Named defect: "the arms are much too big". Draft 42's arms span x 4.25->95.68
  (92 units) against a 46-unit body, with four prongs each. v2: authored arms,
  two prongs, tips at x 16.5/83.5 -> 67-unit span, reach 0.79 of the body radius.
"""
import json
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")
from svg_pipeline import spectrum, validate  # noqa: E402

VIOLIN_HALF = [
    (50.0, 2.2), (53.6, 2.8), (55.2, 6.0), (54.0, 9.4), (52.8, 10.4),
    (52.8, 15.0), (52.4, 36.6), (54.0, 38.6), (59.0, 39.4), (63.4, 42.0),
    (64.6, 45.6), (62.6, 49.2), (59.0, 52.8), (59.8, 56.6), (63.6, 59.2),
    (67.0, 62.6), (68.2, 68.0), (67.6, 74.0), (65.4, 80.5), (61.8, 87.0),
    (57.6, 92.8), (53.4, 96.6), (50.0, 97.8),
]
ARM = [  # left arm, from ball point (31.7,43.64) to ball point (34.8,34.63)
    (26.0, 40.5), (19.5, 41.0), (16.5, 37.0), (22.0, 33.5),
    (18.0, 29.0), (21.0, 28.0), (25.0, 32.0), (23.5, 22.0),
    (27.0, 23.0), (31.0, 31.5),
]


def mirror(half):
    return [list(p) for p in half] + [[100.0 - x, y] for x, y in reversed(half[1:-1])]


violin = mirror(VIOLIN_HALF)

snow_src = json.load(open("/opt/workspace/projects/fourier/drafts/20261030-0602-snowman/snowman-dots.json"))
snowman = (snow_src[:10] + [list(p) for p in ARM] + snow_src[20:31]
           + [[100.0 - x, y] for x, y in reversed(ARM)] + snow_src[41:])


def preview(dots, path):
    fig = plt.figure(figsize=(7.0, 3.5), dpi=100)
    ax = fig.add_axes([0.01, 0.02, 0.47, 0.9])
    ax.plot([p[0] for p in dots] + [dots[0][0]], [p[1] for p in dots] + [dots[0][1]],
            ls=(0, (3, 2.6)), lw=2, color="black", solid_capstyle="round")
    ax.set_title("as the toy draws it", fontsize=9)
    ax2 = fig.add_axes([0.51, 0.02, 0.47, 0.9])
    ax2.fill([p[0] for p in dots], [p[1] for p in dots], color="#e8e8e8", ec="none")
    ax2.plot([p[0] for p in dots] + [dots[0][0]], [p[1] for p in dots] + [dots[0][1]],
             lw=1, color="black")
    ax2.scatter([p[0] for p in dots], [p[1] for p in dots], s=6, color="crimson", zorder=3)
    ax2.set_title(f"dot order, n={len(dots)}", fontsize=9)
    for a in (ax, ax2):
        a.set_xlim(0, 100)
        a.set_ylim(100, 0)
        a.set_aspect("equal")
        a.set_xticks([])
        a.set_yticks([])
        for sp in a.spines.values():
            sp.set_visible(False)
    fig.savefig(path)
    plt.close(fig)


for name, dots, path in (("violin", violin, "violin-v2-preview.png"),
                         ("snowman", snowman, "snowman-v2-preview.png")):
    issues, gap = validate(dots)
    ranked, ratio, share = spectrum(dots)
    print(f"{name:8s} n={len(dots):3d} gap={gap:5.2f} issues={len(issues) if issues else 0} "
          f"share={share*100:5.1f}% c4:c5={ratio:4.2f} k={[k for _, k in ranked[:4]]}")
    if issues:
        print("   ", issues[:3])
    preview(dots, path)
    json.dump(dots, open(f"{name}-v2-dots.json", "w"))
print("wrote previews + dot lists")
