"""Exact toy-scale pair: each panel is 340x340 px, lw 1.6, dashed, no fill."""
import json
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image, ImageDraw

OLD = np.array(json.load(open("snowman-branch-dots.json")))
NEW = np.array(json.load(open("snowman-asym2-B-dots.json")))

for tag, P in (("v3", OLD), ("v4", NEW)):
    fig = plt.figure(figsize=(3.4, 3.4), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    Q = np.vstack([P, P[0]])
    ax.plot(Q[:, 0], Q[:, 1], lw=1.6, ls="--", color="#2b2b2b")
    ax.set_xlim(0, 100); ax.set_ylim(100, 0); ax.set_aspect("equal"); ax.axis("off")
    fig.savefig(f"toy-{tag}.png", dpi=100)
    plt.close(fig)

a, b = Image.open("toy-v3.png"), Image.open("toy-v4.png")
out = Image.new("RGB", (a.width + b.width + 40, a.height + 34), "white")
out.paste(a, (0, 34)); out.paste(b, (a.width + 40, 34))
d = ImageDraw.Draw(out)
d.text((4, 8), "v3  mirrored arms (46 dots)", fill="#222")
d.text((a.width + 44, 8), "v4  asymmetric arms (46 dots)", fill="#222")
out.save("asym2-toy-pair.png")
print("ok", out.size)
