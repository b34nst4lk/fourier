#!/usr/bin/env python3
"""Inspect spider ring: radial profile + contiguous leg runs. Read-only."""
import json
import math

import numpy as np

d = json.load(open("/opt/workspace/projects/fourier/drafts/20261104-0201/spider-dots.json"))
dots = np.array(d["dots"] if isinstance(d, dict) else d, float)
n = len(dots)
C = dots.mean(0)
r = np.linalg.norm(dots - C, axis=1)
print("centroid", C.round(2), "n", n)
print("radius: min %.2f med %.2f max %.2f" % (r.min(), np.median(r), r.max()))
for i, ((x, y), ri) in enumerate(zip(dots, r)):
    print(f"{i:>2} ({x:>6.2f},{y:>6.2f}) r={ri:>5.2f} ang={math.degrees(math.atan2(y - C[1], x - C[0])):>7.1f}")

# contiguous runs above a radius threshold
R = float(np.median(r)) * 1.12
mask = r > R
print("\nthreshold R =", round(R, 2))
runs = []
i = 0
order = list(range(n))
# rotate so run doesn't wrap
start = next(k for k in order if not mask[k])
seq = [(start + k) % n for k in range(n)]
cur = []
for idx in seq:
    if mask[idx]:
        cur.append(idx)
    else:
        if cur:
            runs.append(cur)
            cur = []
if cur:
    runs.append(cur)
print("leg runs:", runs)
for run in runs:
    pts = dots[run]
    print(f"  run {run[0]}-{run[-1]} ({len(run)} pts) rmax={np.linalg.norm(pts-C,axis=1).max():.1f}")
