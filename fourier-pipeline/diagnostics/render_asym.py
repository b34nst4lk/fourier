"""Toy-scale strip: symmetric v3 vs the three asymmetry levels, plus an arm zoom."""
import json
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

SETS = [("v3 mirror", "snowman-branch-dots.json"), ("A mild", "asym-A-mild-dots.json"),
        ("B medium", "asym-B-medium-dots.json"), ("C bold", "asym-C-bold-dots.json")]

fig, axes = plt.subplots(2, 4, figsize=(13.6, 7.4), dpi=110,
                         gridspec_kw=dict(height_ratios=[1, 1.25]))
for col, (name, path) in enumerate(SETS):
    P = np.array(json.load(open(path)), float)
    Q = np.vstack([P, P[:1]])
    gap = float(np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1).min())
    for row in (0, 1):
        ax = axes[row][col]
        ax.plot(Q[:, 0], Q[:, 1], lw=1.6, color="#2b2b2b", ls=(0, (3, 2.6)))
        ax.set_aspect("equal")
        if row == 0:
            ax.set_xlim(0, 100); ax.set_ylim(100, 0)
            ax.set_title(f"{name}   n={len(P)} gap={gap:.2f}", fontsize=10)
        else:
            ax.set_xlim(11, 52); ax.set_ylim(60, 18)
            ax.set_title("arms 2.4x", fontsize=9)
        ax.set_xticks([]); ax.set_yticks([])
        for s in ax.spines.values():
            s.set_visible(False)
fig.suptitle("snowman arms: body-side angle and twig angle, mirrored vs asymmetric", fontsize=12)
fig.tight_layout()
fig.savefig("asym-ladder.png", facecolor="white")

# toy scale alone, one row, real pixel size (100 units = 340 px)
fig2, axs = plt.subplots(1, 4, figsize=(13.6, 3.4), dpi=100)
for ax, (name, path) in zip(axs, SETS):
    P = np.array(json.load(open(path)), float)
    Q = np.vstack([P, P[:1]])
    ax.plot(Q[:, 0], Q[:, 1], lw=1.6, color="#2b2b2b", ls=(0, (3, 2.6)))
    ax.set_aspect("equal"); ax.set_xlim(-2, 102); ax.set_ylim(102, -2)
    ax.set_title(name, fontsize=10)
    ax.set_xticks([]); ax.set_yticks([])
    for s in ax.spines.values():
        s.set_visible(False)
fig2.tight_layout()
fig2.savefig("asym-toy.png", facecolor="white")
print("ok")
