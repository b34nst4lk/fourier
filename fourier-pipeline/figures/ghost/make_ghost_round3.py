"""Ghost v3: shallow scalloped hem, round eye pockets, judged at true toy scale.

Hem amplitude was 14 over a 9.65-unit lobe -> a 28-unit-deep tooth, which renders
as a zigzag no matter how finely it is sampled. Now A=6, y0=79: peak-to-valley is
12 against a 9.65 half-width, i.e. a scallop.

Third panel draws at the toy's real proportion (100 units -> 340 px, 2 px dashed
stroke) because a 0.8-unit crease is 2.7 px there and merges into one line,
while a magnified matplotlib panel shows it as two separate walls.
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
HEM_Y0, HEM_A, HEM_HALF = 79.0, 6.0, 29.0


def hem_y(x):
    return HEM_Y0 + HEM_A * math.cos(3 * math.pi * (x - 50.0) / HEM_HALF)


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
print("hem y:", [f"{hem_y(x):.1f}" for x in (79, 74, 69.3, 64, 60, 55, 50)])

ring = np.vstack([d, d[:1]])

fig = plt.figure(figsize=(13.0, 4.6))
ax1 = fig.add_subplot(1, 3, 1)
ax1.plot(ring[:, 0], ring[:, 1], ls=(0, (3, 2.6)), color="black", lw=1.8)
ax1.set_title("dashed, magnified", fontsize=9)
ax2 = fig.add_subplot(1, 3, 2)
ax2.fill(ring[:, 0], ring[:, 1], color="0.88", lw=0)
ax2.plot(ring[:, 0], ring[:, 1], "-", color="black", lw=1.0)
ax2.plot(d[:, 0], d[:, 1], "o", color="tab:red", ms=2.0)
ax2.set_title(f"filled  n={len(dots)}  {'PASS' if not errs else 'FAIL'}", fontsize=9)
ax3 = fig.add_subplot(1, 3, 3)
ax3.plot(ring[:, 0], ring[:, 1], ls=(0, (1.2, 1.05)), color="black", lw=0.42)
ax3.set_title("toy scale: 340 px, 2 px dash", fontsize=9)
for ax in (ax1, ax2, ax3):
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
fig.tight_layout()
fig.savefig("ghost-round3.png", dpi=140)

# true toy-scale copy, no matplotlib scaling tricks
fig2, ax = plt.subplots(figsize=(3.4, 3.4), dpi=100)
ax.plot(ring[:, 0], ring[:, 1], ls=(0, (3, 2.6)), color="black", lw=2.0)
ax.set_xlim(0, 100)
ax.set_ylim(100, 0)
ax.set_aspect("equal")
ax.axis("off")
fig2.subplots_adjust(0, 0, 1, 1)
fig2.savefig("ghost-round3-toyscale.png", dpi=100)
print("wrote ghost-round3.png and ghost-round3-toyscale.png")

if not errs:
    json.dump(dots, open("ghost-round3-dots.json", "w"), indent=1)
    print("wrote ghost-round3-dots.json")
