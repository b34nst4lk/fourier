"""Param sweep at true toy scale: hem amplitude x eye inset.

At 340 px the crease is 3 px tall, so it disappears unless the eye is inset far
from the edge. And a 12-unit peak-to-valley over a 9.65-unit half-width is a
tooth, not a scallop, whatever the sampling. Four candidates, all n<=50.
"""
import importlib.util
import math

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

SPEC = "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts/svg_pipeline.py"
_s = importlib.util.spec_from_file_location("sp", SPEC)
sp = importlib.util.module_from_spec(_s)
_s.loader.exec_module(sp)

GAP, N_ARC = 0.8, 11


def build(hem_a, hem_y0, eye_cx, eye_cy=52.0, rx=6.0, ry=5.0, half_w=29.0):
    def hem_y(x):
        return hem_y0 + hem_a * math.cos(3 * math.pi * (x - 50.0) / half_w)

    half = [
        (50.0, 17.0), (58.0, 17.8), (66.0, 21.0), (73.0, 27.0),
        (77.0, 35.0), (79.0, 42.0), (79.0, 58.0),
        (74.0, hem_y(74.0)), (69.3, hem_y(69.3)), (64.0, hem_y(64.0)),
        (60.0, hem_y(60.0)), (55.0, hem_y(55.0)), (50.0, hem_y(50.0)),
    ]

    y_up, y_lo = eye_cy - GAP / 2, eye_cy + GAP / 2
    a0 = math.asin((y_up - eye_cy) / ry)
    a1 = math.asin((y_lo - eye_cy) / ry) - 2 * math.pi
    arc = [
        (eye_cx + rx * math.cos(a0 + (a1 - a0) * i / (N_ARC - 1)),
         eye_cy + ry * math.sin(a0 + (a1 - a0) * i / (N_ARC - 1)))
        for i in range(N_ARC)
    ]
    pocket = [(79.0, y_up)] + arc + [(79.0, y_lo)]

    i = half.index((79.0, 58.0))
    right = half[:i] + pocket + half[i:]
    return right + [(100.0 - x, y) for (x, y) in reversed(right[1:-1])]


VARIANTS = [
    ("A=3.5  eye x=70", dict(hem_a=3.5, hem_y0=76.0, eye_cx=70.0)),
    ("A=3.5  eye x=68", dict(hem_a=3.5, hem_y0=76.0, eye_cx=68.0)),
    ("A=5.0  eye x=70", dict(hem_a=5.0, hem_y0=77.0, eye_cx=70.0)),
    ("A=2.5  eye x=71", dict(hem_a=2.5, hem_y0=75.0, eye_cx=71.0)),
]

fig, axes = plt.subplots(1, 4, figsize=(13.6, 3.7), dpi=100)
for ax, (label, kw) in zip(axes, VARIANTS):
    dots = build(**kw)
    errs, md = sp.validate(dots)
    _, ratio, share = sp.spectrum(dots)
    d = np.asarray(dots, float)
    ring = np.vstack([d, d[:1]])
    ax.plot(ring[:, 0], ring[:, 1], ls=(0, (3, 2.6)), color="black", lw=2.0)
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_title(f"{label}\nn={len(dots)} {'PASS' if not errs else 'FAIL'} {share*100:.0f}% c4c5={ratio:.2f}",
                 fontsize=8)
fig.tight_layout()
fig.savefig("ghost-sweep.png")
print("wrote ghost-sweep.png")
