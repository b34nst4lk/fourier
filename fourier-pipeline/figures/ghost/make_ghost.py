"""Ghost with cut-out eyes, tuned to the 12-30 dot budget.

A closed loop cannot enclose a hole (Jordan: its interior is simply connected),
so each eye is a pocket cut in from the silhouette edge through a hairline
corridor. Corridor walls sit ~1 unit apart, so on the dashed target the eye
reads as a hole and the corridor as a faint crease.
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


def mirror(half):
    return [tuple(p) for p in half] + [(100.0 - x, y) for (x, y) in reversed(half[1:])]


def corridor_eye(mouth_y, tip, half_w, gap):
    """Right side, travelling downward: edge -> corridor in -> pocket -> corridor out -> edge.

    Order matters: leave the corridor through the *lower* lip, otherwise the
    continuing edge segment runs straight through the mouth and self-intersects.
    """
    up = mouth_y - gap / 2
    lo = mouth_y + gap / 2
    m_up = (78.0, up)
    a_up = (70.0, up)
    b = (66.0, tip[0])
    c = (tip[1], mouth_y)
    d = (66.0, tip[2])
    a_lo = (70.0, lo)
    m_lo = (78.0, lo)
    return [m_up, a_up, b, c, d, a_lo, m_lo]


def wedge_eye(mouth_y, gap):
    up = mouth_y - gap / 2
    lo = mouth_y + gap / 2
    return [
        (78.0, up), (70.0, up),
        (63.0, up - 8.0), (63.0, lo + 8.0),
        (70.0, lo), (78.0, lo),
    ]


def build(body, eye):
    """Insert `eye` into the right side between (78,50)-ish and (78,66)."""
    i = body.index((78.0, 66)) if (78.0, 66) in body else len(body) - 3
    return mirror(body[:i] + eye + body[i:])


BODY_A = [(50, 20), (59, 22), (69, 29), (76, 40), (78, 52), (78, 66), (71, 88), (60, 74)]
BODY_B = [(50, 20), (58, 21.5), (67, 27), (74, 37), (78, 50), (78, 66),
          (72, 88), (63, 74), (54, 88)]

VARIANTS = [
    ("P1 diamond eyes", build(BODY_A, corridor_eye(55.0, (47.5, 58.5, 62.5), 56, 1.2))),
    ("P2 wedge eyes", build(BODY_B, wedge_eye(54.0, 1.2))),
    ("P3 control no eyes", mirror(BODY_B)),
]

fig, axes = plt.subplots(1, 3, figsize=(12.5, 4.8))
best = []
for (name, dots), ax in zip(VARIANTS, axes):
    errs, md = sp.validate(dots)
    amps, ratio, share = sp.spectrum(dots)
    ks = [k for _, k in amps[:4]]
    print(f"{name:20s} n={len(dots):2d} min_gap={md:5.2f} share={share*100:5.1f}% "
          f"c4:c5={ratio:4.2f} dials={ks} "
          f"{'PASS' if not errs else 'FAIL: ' + '; '.join(errs)}")
    d = np.asarray(dots, float)
    ring = np.vstack([d, d[:1]])
    ax.fill(ring[:, 0], ring[:, 1], color="0.90", lw=0)
    ax.plot(ring[:, 0], ring[:, 1], "-", color="black", lw=1.4)
    ax.plot(d[:, 0], d[:, 1], "o", color="tab:red", ms=3)
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_title(f"{name}  n={len(dots)}  {'OK' if not errs else 'FAIL'}", fontsize=10)
    if not errs:
        best.append((name, dots, md, share, ratio))
fig.tight_layout()
fig.savefig("ghost-tuned.png", dpi=120)
print("wrote ghost-tuned.png")

if best:
    name, dots, md, share, ratio = best[0]
    with open("ghost-dots-candidate.json", "w") as f:
        json.dump(dots, f, indent=1)
    print("candidate ->", name, len(dots), "dots")
