#!/usr/bin/env python3
"""Hand-built Disney-style castle v3.

v1 read as a crown (bare triangles on a wall).  v2 read as a canyon with pins: the span
between towers was 8 wide and 24 deep, so 2.5-wide merlons hung like teeth.  v3 widens the
curtain wall to 18, gives each merlon 5x6 with 4-unit embrasures, and shortens the exposed
tower bodies to 18 (y=70 -> 52).  Eave overhangs dropped: they rendered as stray ledges.

28 dots: right half + mirror (skill rule: mirror only right[1:-1], so the central spire apex
and the bottom centre stay single points).
"""
import json, sys
import numpy as np

sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")
import svg_pipeline as S

# (x, y) y-down, clockwise from the central spire apex to the bottom centre.
RIGHT = [
    (50.0,  6.0),   # 0  central spire apex
    (56.0, 40.0),   # 1  keep roof eave / body right wall top
    (56.0, 64.0),   # 2  keep wall down to merlon level
    (61.0, 64.0),   # 3  merlon A top
    (61.0, 70.0),   # 4  embrasure
    (65.0, 70.0),   # 5  embrasure floor
    (65.0, 64.0),   # 6  merlon B, up
    (70.0, 64.0),   # 7  merlon B top
    (70.0, 70.0),   # 8  embrasure
    (74.0, 70.0),   # 9  curtain wall runs into tower
    (74.0, 52.0),   # 10 right tower body, top of left wall
    (80.0, 22.0),   # 11 right tower spire apex
    (86.0, 52.0),   # 12 right tower roof, right eave
    (86.0, 94.0),   # 13 ground
    (50.0, 94.0),   # 14 bottom centre
]

dots = np.asarray(RIGHT + [(100.0 - x, y) for x, y in reversed(RIGHT[1:-1])], float)

v = S.validate(dots)
ranked, ratio, share = S.spectrum(dots)
print("validate:", v)
print("c4:c5 =", round(ratio, 3), " energy in 4 dials =", round(100 * share, 1), "%")
print("dials:", [(round(a, 2), k) for a, k in ranked[:4]])

meta = {"n": len(dots), "iou": 1.0, "min_adj": v[1], "ratio": ratio}
S.preview("castle", dots, dots, meta, "castle-preview.png")
json.dump([[round(x, 2), round(y, 2)] for x, y in dots], open("castle-dots.json", "w"), indent=1)

xs, ys = dots[:, 0], dots[:, 1]
print(f"n={len(dots)} xrange={xs.min():.2f}-{xs.max():.2f} yrange={ys.min():.2f}-{ys.max():.2f}")
