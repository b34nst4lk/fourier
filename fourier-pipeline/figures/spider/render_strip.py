#!/usr/bin/env python3
"""Render N dots files as toy-scale (340px) dashed panels side by side."""
import json
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

files = sys.argv[2:]
out = sys.argv[1]
fig, axes = plt.subplots(1, len(files), figsize=(3.4 * len(files), 3.9), dpi=100)
axes = [axes] if len(files) == 1 else list(axes)
for ax, f in zip(axes, files):
    d = json.load(open(f))
    P = d["dots"] if isinstance(d, dict) else d
    xs = [p[0] for p in P] + [P[0][0]]
    ys = [p[1] for p in P] + [P[0][1]]
    ax.plot(xs, ys, color="#1b1a17", lw=1.152, ls=(0, (2.16, 1.87)))
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    for s in ax.spines.values():
        s.set_visible(False)
    ax.set_title(f.split("/")[-1].replace("-dots.json", ""), fontsize=7, color="#555")
plt.tight_layout()
plt.savefig(out, dpi=100, facecolor="white")
print("wrote", out)
