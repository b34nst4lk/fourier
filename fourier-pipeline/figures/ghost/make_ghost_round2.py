"""Ghost v2: rounded dome, sine-sampled 3-lobe hem, round eye pockets, thin stalk.

Budget 50. Body 24 (13 per half) + 2 x (2 mouths + 11 arc) = 50.
Hem sampled from y = 72 + 14*cos(3*pi*(x-50)/29) so lobes hang down and the
valleys between them are smooth, not V-notches.
Crease thinned 1.2 -> 0.8: the two corridor lips merge into one dash at toy
scale instead of reading as a double stem.
"""
import importlib.util
import json
import math

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

SPEC = "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts/svg_pipeline.py"
_s = importlib.util.spec_from_file_location("sp", SPEC)
sp = importlib.util.module_from_spec(_s)
_s.loader.exec_module(sp)

EYE_CX, EYE_CY, RX, RY = 68.0, 52.0, 6.0, 5.0
GAP, N_ARC = 0.8, 11


def hem_y(x):
    return 72.0 + 14.0 * math.cos(3 * math.pi * (x - 50.0) / 29.0)


HALF = [
    (50.0, 17.0), (58.0, 17.8), (66.0, 21.0), (73.0, 27.0),
    (77.0, 35.0), (79.0, 42.0), (79.0, 58.0),
    (74.0, hem_y(74.0)), (69.3, hem_y(69.3)), (64.0, hem_y(64.0)),
    (60.0, hem_y(60.0)), (55.0, hem_y(55.0)), (50.0, hem_y(50.0)),
]


def eye_pocket():
    y_up, y_lo = EYE_CY - GAP / 2, EYE_CY + GAP / 2
    a0 = math.asin((y_up - EYE_CY) / RY)
    a1 = math.asin((y_lo - EYE_CY) / RY) - 2 * math.pi
    arc = [
        (EYE_CX + RX * math.cos(a0 + (a1 - a0) * i / (N_ARC - 1)),
         EYE_CY + RY * math.sin(a0 + (a1 - a0) * i / (N_ARC - 1)))
        for i in range(N_ARC)
    ]
    return [(79.0, y_up)] + arc + [(79.0, y_lo)]


def build():
    i = HALF.index((79.0, 58.0))
    right = HALF[:i] + eye_pocket() + HALF[i:]
    return right + [(100.0 - x, y) for (x, y) in reversed(right[1:-1])]


dots = build()
errs, md = sp.validate(dots)
amps, ratio, share = sp.spectrum(dots)
ks = [k for _, k in amps[:4]]
d = np.asarray(dots, float)
print(f"n={len(dots)} min_gap={md:.2f} share={share*100:.1f}% c4:c5={ratio:.2f} dials={ks}")
print("validate:", "PASS" if not errs else "FAIL: " + "; ".join(errs))

fig, axes = plt.subplots(1, 2, figsize=(9.5, 4.8))
ring = np.vstack([d, d[:1]])
axes[0].plot(ring[:, 0], ring[:, 1], ls=(0, (3, 2.6)), color="black", lw=1.8)
axes[0].set_title("as the toy draws it (dashed, no fill)", fontsize=10)
axes[1].fill(ring[:, 0], ring[:, 1], color="0.88", lw=0)
axes[1].plot(ring[:, 0], ring[:, 1], "-", color="black", lw=1.0)
axes[1].plot(d[:, 0], d[:, 1], "o", color="tab:red", ms=2.2)
axes[1].set_title(f"n={len(dots)}  {'PASS' if not errs else 'FAIL'}", fontsize=10)
for ax in axes:
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
fig.tight_layout()
fig.savefig("ghost-round2.png", dpi=140)
print("wrote ghost-round2.png")

if not errs:
    json.dump(dots, open("ghost-round2-dots.json", "w"), indent=1)
    print("wrote ghost-round2-dots.json")
