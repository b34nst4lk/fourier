"""Toy-scale strip: v3 (mirrored) vs A/B/C asymmetric; row 2 zooms both arms."""
import json
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import make_asym2 as M

SETS = [("v3 mirrored", json.load(open("snowman-branch-dots.json")))]
for k, (lk, rk) in M.LEVELS.items():
    SETS.append((f"{k} asym", M.build(lk, rk)))

fig = plt.figure(figsize=(16, 8.6))
for i, (name, P) in enumerate(SETS):
    P = np.array(P)
    Q = np.vstack([P, P[0]])
    ax = fig.add_subplot(2, 4, i + 1)
    ax.plot(Q[:, 0], Q[:, 1], lw=1.6, ls="--", color="#2b2b2b")
    ax.set_xlim(0, 100); ax.set_ylim(100, 0); ax.set_aspect("equal")
    ax.set_title(f"{name}  (toy scale)", fontsize=9); ax.axis("off")
    ax = fig.add_subplot(2, 4, i + 5)
    ax.plot(Q[:, 0], Q[:, 1], lw=1.9, ls="-", color="#2b2b2b")
    ax.plot(P[:, 0], P[:, 1], "o", ms=2.4, color="#c0392b")
    ax.set_xlim(12, 50); ax.set_ylim(56, 20); ax.set_aspect("equal")
    ax.set_title(f"{name}  2.4x left arm", fontsize=9); ax.axis("off")
fig.tight_layout()
fig.savefig("asym2-ladder.png", dpi=150)
print("ok")
