"""Ghost with rounded cut-out eyes, tuned to the 50-dot budget.

One closed loop cannot enclose a hole (Jordan), so each eye is a pocket cut in
from the silhouette edge through a 1.2-unit corridor. Here the pocket itself is
an elliptical arc (rx=6, ry=5) sampled at ~29 deg steps, so it reads round
rather than as a diamond. Corridor lips land exactly on the vertical side run
at x=78, so no segment rides along the body edge.
"""
import importlib.util
import json
import math

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

SPEC = "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts/svg_pipeline.py"
_spec = importlib.util.spec_from_file_location("sp", SPEC)
sp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sp)

# right half, top centre -> side -> 3-lobe hem -> bottom centre
HALF = [
    (50.0, 20.0), (60.0, 22.0), (70.0, 31.0), (78.0, 44.0),
    (78.0, 58.0), (72.0, 86.0), (62.0, 71.0), (50.0, 88.0),
]

EYE_CX, EYE_CY, RX, RY = 66.0, 52.0, 6.0, 5.0
GAP = 1.2
N_ARC = 13          # arc samples including both lips -> 11 interior


def eye_pocket():
    """Travelling down the right edge: mouth in -> round pocket -> mouth out."""
    y_up, y_lo = EYE_CY - GAP / 2, EYE_CY + GAP / 2
    # angle of each lip on the ellipse, measured from +x, y-down
    phi_up = math.asin((y_up - EYE_CY) / RY)
    phi_lo = math.asin((y_lo - EYE_CY) / RY)
    # long way round: decreasing phi from the upper lip past the top and left
    start, end = phi_up, phi_lo - 2 * math.pi
    pts = []
    for i in range(N_ARC):
        phi = start + (end - start) * i / (N_ARC - 1)
        pts.append((EYE_CX + RX * math.cos(phi), EYE_CY + RY * math.sin(phi)))
    return [(78.0, y_up)] + pts + [(78.0, y_lo)]


def build():
    right = HALF[:HALF.index((78.0, 58.0))] + eye_pocket() + HALF[HALF.index((78.0, 58.0)):]
    return right + [(100.0 - x, y) for (x, y) in reversed(right[1:-1])]


dots = build()
errs, md = sp.validate(dots)
amps, ratio, share = sp.spectrum(dots)
ks = [k for _, k in amps[:4]]

d = np.asarray(dots, float)
pairs = [
    (np.linalg.norm(d[i] - d[j]), i, j)
    for i in range(len(d)) for j in range(i + 2, len(d))
    if not (i == 0 and j == len(d) - 1)
]
worst, wi, wj = min(pairs)
print(f"n={len(dots)} min_gap={md:.2f} closest_non_adjacent={worst:.2f} "
      f"(pts {wi},{wj}) share={share*100:.1f}% c4:c5={ratio:.2f} dials={ks}")
print("validate:", "PASS" if not errs else "FAIL: " + "; ".join(errs))

fig, axes = plt.subplots(1, 2, figsize=(9.5, 4.8))
ring = np.vstack([d, d[:1]])
axes[0].plot(ring[:, 0], ring[:, 1], ls=(0, (3, 2.6)), color="black", lw=1.8)
axes[0].set_title("as the toy draws it (dashed, no fill)", fontsize=10)
axes[1].fill(ring[:, 0], ring[:, 1], color="0.88", lw=0)
axes[1].plot(ring[:, 0], ring[:, 1], "-", color="black", lw=1.2)
axes[1].plot(d[:, 0], d[:, 1], "o", color="tab:red", ms=2.8)
axes[1].set_title(f"n={len(dots)}  {'PASS' if not errs else 'FAIL'}", fontsize=10)
for ax in axes:
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
fig.tight_layout()
fig.savefig("ghost-round.png", dpi=140)
print("wrote ghost-round.png")

if not errs:
    json.dump(dots, open("ghost-round-dots.json", "w"), indent=1)
    print("wrote ghost-round-dots.json")
