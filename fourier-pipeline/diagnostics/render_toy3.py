"""Three panels at exact toy scale (340 px each): v3 mirrored, B, D."""
import json
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image, ImageDraw

SETS = [("v3  mirrored", "snowman-branch-dots.json"),
        ("B   steep-left, wide right fork", "snowman-asym2-B-dots.json"),
        ("D   shallow-left, steep right", "asym2-D-dots.json")]

imgs = []
for tag, path in SETS:
    P = np.array(json.load(open(path)))
    fig = plt.figure(figsize=(3.4, 3.4), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    Q = np.vstack([P, P[0]])
    ax.plot(Q[:, 0], Q[:, 1], lw=1.6, ls="--", color="#2b2b2b")
    ax.set_xlim(0, 100); ax.set_ylim(100, 0); ax.set_aspect("equal"); ax.axis("off")
    fig.savefig("_t.png", dpi=100); plt.close(fig)
    imgs.append((tag, Image.open("_t.png").copy()))

w = sum(i.width for _, i in imgs) + 30 * (len(imgs) - 1)
out = Image.new("RGB", (w, 340 + 30), "white")
d = ImageDraw.Draw(out)
x = 0
for tag, im in imgs:
    out.paste(im, (x, 30)); d.text((x + 4, 8), tag, fill="#222"); x += im.width + 30
out.save("asym2-toy3.png")
print("ok", out.size)
