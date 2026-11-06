import json
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

V2 = "/opt/workspace/tmp/fourier-svg/violin-snowman/snowman-v2-dots.json"
PANELS = [("v2 (current)", V2), ("brA L15 t30", "brA-dots.json"), ("brB L17.5 t34", "brB-dots.json"),
          ("brC L20 t38", "brC-dots.json"), ("brD no fork", "brD-dots.json")]
PX = 340
fig, axes = plt.subplots(1, len(PANELS), figsize=(len(PANELS) * (PX + 14) / 100, (PX + 34) / 100), dpi=100)
for ax, (title, src) in zip(axes, PANELS):
    P = np.array(json.load(open(src)))
    ax.plot(np.append(P[:, 0], P[0, 0]), np.append(P[:, 1], P[0, 1]),
            ls=(0, (3, 2)), lw=1.6, color="black", solid_joinstyle="miter", dash_capstyle="butt")
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title(title, fontsize=8)
fig.subplots_adjust(0.005, 0.04, 0.995, 0.96, 0.01)
fig.savefig("strip-branch.png", dpi=100)
print("wrote strip-branch.png")
