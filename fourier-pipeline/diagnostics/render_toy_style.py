"""Render candidate ghosts the way the toy actually draws them: dashed, unfilled,
at toy scale (ffi.mjs:464-476 — `setLineDash([3,2.6])`, stroke, never fill).
"""
import json

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

cands = json.load(open("ghost-dots-candidate.json"))
control = json.load(open("p3-dots.json")) if False else None

CTRL = [(50, 20), (58, 21.5), (67, 27), (74, 37), (78, 50), (78, 66),
        (72, 88), (63, 74), (54, 88)]
ctrl = CTRL + [(100.0 - x, y) for x, y in reversed(CTRL[1:])]

fig, axes = plt.subplots(1, 4, figsize=(14, 4.2))
for ax, (title, dots, fill) in zip(
    axes,
    [
        ("P1 eyes — dashed, as the toy draws it", cands, False),
        ("P1 eyes — if the toy filled instead", cands, True),
        ("control no eyes — dashed", ctrl, False),
        ("control no eyes — filled", ctrl, True),
    ],
):
    d = np.asarray(dots, float)
    ring = np.vstack([d, d[:1]])
    if fill:
        ax.fill(ring[:, 0], ring[:, 1], color="0.88", lw=0)
    ax.plot(ring[:, 0], ring[:, 1], ls=(0, (3, 2.6)) if not fill else "-",
            color="black", lw=1.6)
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_title(title, fontsize=9)
fig.suptitle("ghost candidates at toy rendering (dashed stroke, no fill)", fontsize=11)
fig.tight_layout()
fig.savefig("ghost-as-toy-draws.png", dpi=130)
print("wrote ghost-as-toy-draws.png")
