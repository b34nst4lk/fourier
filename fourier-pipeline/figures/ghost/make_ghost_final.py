"""Ghost with cut-out eyes — final candidate.

Body: mirrored half, 15 dots, 3-lobe hem, vertical side runs so the eye
corridor mouths land exactly on the silhouette edge.

Eyes: diamond pocket cut in from the side edge through a 1.2-unit corridor.
A closed loop cannot enclose a hole, so the corridor is the price of the
cut-out; at 1.2 units it reads as the eye's crease, not a stem.
"""
import importlib.util
import json

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

SPEC = "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts/svg_pipeline.py"
_spec = importlib.util.spec_from_file_location("sp", SPEC)
sp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sp)

# half: top centre -> right side -> hem -> bottom centre. 8 points -> 15 dots.
HALF = [
    (50.0, 20.0), (60.0, 22.0), (70.0, 31.0), (78.0, 44.0),
    (78.0, 58.0), (72.0, 86.0), (62.0, 71.0), (50.0, 88.0),
]


def mirror(half):
    return [tuple(p) for p in half] + [(100.0 - x, y) for (x, y) in reversed(half[1:-1])]


def corridor_eye(mouth_y, gap=1.2):
    """Travelling down the right edge: stub -> corridor in -> pocket -> corridor out."""
    up, lo = mouth_y - gap / 2, mouth_y + gap / 2
    return [
        (78.0, up), (70.0, up),        # corridor, upper wall
        (66.0, 45.0), (58.5, mouth_y), (66.0, 59.0),   # diamond pocket
        (70.0, lo), (78.0, lo),        # corridor, lower wall
    ]


def build(half, eye):
    i = half.index((78.0, 58.0))          # insert on the side run, above the hem
    return mirror(half[:i] + eye + half[i:])


dots = build(HALF, corridor_eye(52.0))
errs, md = sp.validate(dots)
amps, ratio, share = sp.spectrum(dots)
ks = [k for _, k in amps[:4]]
print(f"n={len(dots)} min_gap={md:.2f} share={share*100:.1f}% c4:c5={ratio:.2f} "
      f"dials={ks} {'PASS' if not errs else 'FAIL: ' + '; '.join(errs)}")

# nearest non-adjacent approach = the corridor gap itself
d = np.asarray(dots, float)
worst = min(
    np.linalg.norm(d[i] - d[j])
    for i in range(len(d)) for j in range(i + 2, len(d)) if not (i == 0 and j == len(d) - 1)
)
print(f"closest non-adjacent pair={worst:.2f} (corridor width)")

fig, axes = plt.subplots(1, 2, figsize=(9.5, 4.6))
ring = np.vstack([d, d[:1]])
axes[0].plot(ring[:, 0], ring[:, 1], ls=(0, (3, 2.6)), color="black", lw=1.8)
axes[0].set_title("as the toy draws it (dashed, no fill)", fontsize=10)
axes[1].fill(ring[:, 0], ring[:, 1], color="0.88", lw=0)
axes[1].plot(ring[:, 0], ring[:, 1], "-", color="black", lw=1.4)
axes[1].plot(d[:, 0], d[:, 1], "o", color="tab:red", ms=3)
axes[1].set_title(f"n={len(dots)}  {'PASS' if not errs else 'FAIL'}", fontsize=10)
for ax in axes:
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
fig.tight_layout()
fig.savefig("ghost-final.png", dpi=140)
print("wrote ghost-final.png")

if not errs:
    with open("ghost-dots.json", "w") as f:
        json.dump(dots, f, indent=1)
    print("wrote ghost-dots.json")
