#!/usr/bin/env python3
"""Slim the spider's legs: narrow each leg band about its own centerline.

The ring traces 8 legs as excursions from the body. For each leg we fit a
centerline (mid-root -> mid-tip) and pull every leg vertex onto it by a factor
derived from a target root width and tip width, so leg angles, tips and the
body outline are all preserved -- only the band thickness changes.

Usage: make_slim.py W_ROOT W_TIP OUT_PREFIX   (widths in 0-100 units)
"""
import json
import sys

import numpy as np
from shapely.geometry import LinearRing, Polygon

SRC = "/opt/workspace/projects/fourier/drafts/20261104-0201/spider-dots.json"


def leg_runs(dots, thresh=1.12):
    C = dots.mean(0)
    r = np.linalg.norm(dots - C, axis=1)
    mask = r > np.median(r) * thresh
    n = len(dots)
    start = next(k for k in range(n) if not mask[k])
    seq = [(start + k) % n for k in range(n)]
    runs, cur = [], []
    for idx in seq:
        if mask[idx]:
            cur.append(idx)
        else:
            if cur:
                runs.append(cur)
                cur = []
    if cur:
        runs.append(cur)
    return runs


def slim(dots, w_root, w_tip, thresh=1.12):
    P = dots.copy()
    for run in leg_runs(dots, thresh):
        rb, ra = (run[0] - 1) % len(dots), (run[-1] + 1) % len(dots)
        pts = [rb] + run + [ra]
        root_mid = (dots[rb] + dots[ra]) / 2.0
        tip_mid = (dots[run[0]] + dots[run[-1]]) / 2.0
        axis = tip_mid - root_mid
        L = np.linalg.norm(axis)
        axis = axis / L
        nrm = np.array([-axis[1], axis[0]])
        # current widths at both ends, measured perpendicular to the axis
        w_root_now = abs((dots[rb] - dots[ra]) @ nrm)
        w_tip_now = abs((dots[run[0]] - dots[run[-1]]) @ nrm)
        for idx in pts:
            d = (dots[idx] - root_mid) @ nrm
            s = np.clip(((dots[idx] - root_mid) @ axis) / L, 0.0, 1.0)
            target = (1 - s) * (w_root / 2.0) + s * (w_tip / 2.0)
            now = (1 - s) * (w_root_now / 2.0) + s * (w_tip_now / 2.0)
            new = target if now < 1e-9 else d * (target / now)
            P[idx] = dots[idx] + nrm * (new - d)
    return P


def check(P, name):
    ring = LinearRing(P)
    ok_simple = ring.is_simple
    seg = np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1)
    inside = bool(ring.is_simple) and not Polygon(P).is_empty
    report = {
        "name": name,
        "n": len(P),
        "min_gap": round(float(seg.min()), 2),
        "self_intersection": not ok_simple,
        "in_bounds": bool((P >= 0).all() and (P <= 100).all()),
        "bbox": [round(float(v), 2) for v in P.min(0).tolist() + P.max(0).tolist()],
        "simple": inside,
    }
    return report


def main():
    w_root, w_tip, prefix = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
    d = json.load(open(SRC))
    src = np.array(d["dots"] if isinstance(d, dict) else d, float)
    P = slim(src, w_root, w_tip)
    P = np.round(P, 2)
    rep = check(P, prefix)
    print(json.dumps(rep))
    if rep["self_intersection"] or not rep["in_bounds"] or rep["min_gap"] < 0.5:
        print("REJECT: constraint violation")
        return 1
    out = {"name": f"spider-{prefix}", "dots": P.tolist()}
    json.dump(out, open(f"/opt/workspace/tmp/fourier-svg/spider-slim/{prefix}-dots.json", "w"), indent=1)
    # measured leg widths
    widths = []
    for run in leg_runs(src):
        rb, ra = (run[0] - 1) % len(src), (run[-1] + 1) % len(src)
        root_mid = (src[rb] + src[ra]) / 2.0
        tip_mid = (src[run[0]] + src[run[-1]]) / 2.0
        axis = (tip_mid - root_mid) / np.linalg.norm(tip_mid - root_mid)
        nrm = np.array([-axis[1], axis[0]])
        w0 = abs((src[rb] - src[ra]) @ nrm)
        w1 = abs((src[run[0]] - src[run[-1]]) @ nrm)
        # after
        a0 = abs((P[rb] - P[ra]) @ nrm)
        a1 = abs((P[run[0]] - P[run[-1]]) @ nrm)
        widths.append((run[0], round(float(w0), 2), round(float(a0), 2), round(float(w1), 2), round(float(a1), 2)))
    print("leg  root_before root_after  tip_before tip_after")
    for row in widths:
        print(f"{row[0]:>3}  {row[1]:>10} {row[2]:>10}  {row[3]:>10} {row[4]:>9}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
