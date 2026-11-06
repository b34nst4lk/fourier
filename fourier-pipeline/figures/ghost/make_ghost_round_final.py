"""Ghost with round cut-out eyes — final. n=50, the full allowance.

Body: mirrored half, rounded dome, vertical side run so the eye-corridor mouths
land exactly on the silhouette edge, hem sampled from
    y = 76 + 3.5*cos(3*pi*(x-50)/29)
Amplitude 3.5 against a 9.65-unit half-lobe: peak-to-valley 7 over ~19 units of
lobe width, shallow enough to read as a scalloped sheet instead of teeth. At
A=6 the same sampling read as a spiked crown at toy scale.

Eyes: one closed loop cannot enclose a hole (Jordan), so each eye is a pocket
cut in from the edge: out of the body at (79, y-GAP/2), in along a corridor, all
the way round an 12x10 ellipse, back out at (79, y+GAP/2). Travelling down the
right side the loop must leave through the LOWER lip or the corridor legs cross.
The corridor is GAP=0.8 wide and only 3 units long, so at the toy's 2 px stroke
the two walls merge into a single crease rather than a visible stalk.

Eye arc = 11 samples -> chords of ~3.3 units on a 12-unit-wide eye; fewer reads
as a hexagon at toy scale.
"""
import json
import math

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

import importlib.util

SPEC = "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts/svg_pipeline.py"
_s = importlib.util.spec_from_file_location("sp", SPEC)
sp = importlib.util.module_from_spec(_s)
_s.loader.exec_module(sp)

EYE_CX, EYE_CY, RX, RY = 70.0, 52.0, 6.0, 5.0
GAP, N_ARC = 0.8, 11
HEM_A, HEM_Y0, HEM_HALF = 3.5, 76.0, 29.0


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
    arc = []
    for i in range(N_ARC):
        a = a0 + (a1 - a0) * i / (N_ARC - 1)
        arc.append((EYE_CX + RX * math.cos(a), EYE_CY + RY * math.sin(a)))
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
ring = np.vstack([d, d[:1]])
print(f"n={len(dots)} min_gap={md:.2f} share={share*100:.1f}% c4:c5={ratio:.2f} dials={ks}")
print("validate:", "PASS" if not errs else "FAIL: " + "; ".join(errs))

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.4, 4.4))
ax1.plot(ring[:, 0], ring[:, 1], ls=(0, (3, 2.6)), color="black", lw=2.0)
ax1.set_title("as the toy draws it", fontsize=9)
ax2.fill(ring[:, 0], ring[:, 1], color="0.88", lw=0)
ax2.plot(ring[:, 0], ring[:, 1], "-", color="black", lw=1.0)
ax2.plot(d[:, 0], d[:, 1], "o", color="tab:red", ms=2.2)
for i, (x, y) in enumerate(d):
    if i % 5 == 0:
        ax2.annotate(str(i), (x, y), fontsize=5, color="tab:blue")
ax2.set_title(f"n={len(dots)}  min gap {md:.2f}  {'PASS' if not errs else 'FAIL'}", fontsize=9)
for ax in (ax1, ax2):
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
fig.tight_layout()
fig.savefig("ghost-round-final.png", dpi=140)

if not errs:
    json.dump(dots, open("ghost-round-dots.json", "w"), indent=1)
    print("wrote ghost-round-final.png and ghost-round-dots.json")
else:
    print("NOT WRITING dots: validator failed")
