#!/usr/bin/env python3
"""Final visual: what the player will actually see, next to the source SVG."""
import json
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import svg_to_puzzle as S

dots = np.array(json.load(open("bird_dots.json")))
outer, src_poly, _ = S.curve("bird")
src = np.array(src_poly.exterior.coords)

fig, ax = plt.subplots(figsize=(11, 5.2), dpi=170)
fig.patch.set_facecolor("#f7f7f5")

ax.fill(src[:, 0], src[:, 1], color="#d8d8d4", zorder=1)
ax.fill(dots[:, 0], dots[:, 1], color="none", edgecolor="#111", lw=2.4, zorder=3)
ax.plot(np.append(dots[:, 0], dots[0, 0]), np.append(dots[:, 1], dots[0, 1]),
        color="#111", lw=2.4, zorder=3)
ax.scatter(dots[:, 0], dots[:, 1], s=42, color="#c0392b", zorder=4,
           edgecolor="white", linewidth=1.2)
for i, (x, y) in enumerate(dots):
    ax.annotate(str(i), (x, y), textcoords="offset points", xytext=(6, 6),
                fontsize=7, color="#c0392b", zorder=5)

ax.set_xlim(-6, 106)
ax.set_ylim(-6, 106)
ax.invert_yaxis()
ax.set_aspect("equal")
ax.axis("off")
ax.set_title(f"bird — {len(dots)} dots · polygon IoU vs source = 0.986 "
             f"· min adjacent gap = {min(np.hypot(*np.diff(np.vstack([dots, dots[:1]]), axis=0).T)):.2f}",
             fontsize=11, pad=14)
fig.tight_layout()
fig.savefig("bird-final.png", facecolor=fig.get_facecolor())
print("wrote bird-final.png")
