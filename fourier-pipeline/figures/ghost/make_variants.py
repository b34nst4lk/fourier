"""Ghost variants: can a single closed loop show eyes?

Four legal encodings, all built from the same mirrored half so only the eye
treatment varies. Prints validate() + spectrum() for each, renders one sheet.
"""
import importlib.util
import json
import math

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

SPEC = "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts/svg_pipeline.py"
_spec = importlib.util.spec_from_file_location("sp", SPEC)
sp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sp)


def mirror(half):
    """half: right-side points, top-centre (x=50) to bottom-centre. Mirrored back."""
    right = [tuple(p) for p in half]
    left = [(100.0 - x, y) for (x, y) in reversed(half[1:])]
    return right + left


# ---------------------------------------------------------------- body halves
# 10 points per half -> 18 dots: dome 4, side 2, hem 3.
BODY = [
    (50, 20), (57, 21), (65, 25), (72, 33), (76, 44),
    (78, 56), (78, 68), (72, 88), (63, 74), (55, 88),
]


def half_with_side_keyhole():
    """V3: cavity opens onto the side edge through a 3-unit mouth."""
    h = list(BODY)
    # replace side run (76,44)->(78,56) with: edge, mouth, cavity, mouth, edge
    h = [p for p in h if p != (78, 56)]
    i = h.index((78, 68))
    eye = [(78, 58), (74, 56), (69, 53), (66, 47), (69, 42), (75, 43), (78, 46)]
    return h[:i] + eye + h[i:]


def half_with_top_slot():
    """V4: U-slot cut down from the dome."""
    h = list(BODY)
    i = h.index((65, 25))
    slot = [(68, 25), (66, 42), (58, 42), (60, 24)]
    return h[:i] + slot + h[i:]


def half_with_crack_eye():
    """V2: eye diamond inside the head, joined to the side edge by a 0.6 crack."""
    h = list(BODY)
    i = h.index((78, 56))
    # edge -> crack in -> diamond -> crack out -> edge
    eye = [
        (77.0, 50.0), (72.0, 46.6), (68.0, 45.9),   # crack in, width 0.6
        (63.5, 42.0), (59.0, 45.5), (63.0, 49.0), (68.0, 46.5),  # diamond
        (72.0, 47.2), (77.2, 51.0),                 # crack out
        (78.0, 56),
    ]
    return h[:i] + eye + h[i + 1:]


def report(name, dots, ax):
    errs, md = sp.validate(dots)
    amps, ratio, share = sp.spectrum(dots)
    ks = [k for _, k in amps[:4]]
    ok = "PASS" if not errs else "FAIL: " + "; ".join(errs)
    print(f"{name:22s} n={len(dots):2d} min_gap={md:5.2f} share={share*100:5.1f}% "
          f"c4:c5={ratio:4.2f} dials={ks} {ok}")

    d = np.asarray(dots, float)
    ring = np.vstack([d, d[:1]])
    ax.fill(ring[:, 0], ring[:, 1], color="0.90", lw=0)
    ax.plot(ring[:, 0], ring[:, 1], "-", color="black", lw=1.6)
    ax.plot(d[:, 0], d[:, 1], "o", color="tab:red", ms=3.5)
    ax.set_xlim(0, 100)
    ax.set_ylim(100, 0)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_title(f"{name}  n={len(dots)}  {share*100:.0f}%  {'OK' if not errs else 'FAIL'}",
                 fontsize=10)
    return not errs


VARIANTS = [
    ("V1 no eyes", mirror(BODY)),
    ("V2 crack eyes", mirror(half_with_crack_eye())),
    ("V3 side keyhole", mirror(half_with_side_keyhole())),
    ("V4 top slot", mirror(half_with_top_slot())),
]

fig, axes = plt.subplots(1, 4, figsize=(15.5, 4.6))
good = {}
for (name, dots), ax in zip(VARIANTS, axes):
    good[name] = report(name, dots, ax)
fig.suptitle("ghost with cut-out eyes — legal encodings on one closed loop", fontsize=12)
fig.tight_layout()
fig.savefig("ghost-variants.png", dpi=110)
print("wrote ghost-variants.png")

for name, dots in VARIANTS:
    if good[name]:
        with open(name.split()[0].lower() + "-dots.json", "w") as f:
            json.dump(dots, f, indent=1)
