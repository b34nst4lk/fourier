#!/usr/bin/env python3
"""Parametric slim-leg spider: one closed loop, 8 bent legs, validated.

Body = ellipse; each leg = root pair -> knee pair -> tip pair (6 nodes, 48 total).
"""
import json
import sys

import numpy as np
from shapely.geometry import LineString, Polygon

C = np.array([50.0, 57.0])
RX, RY = 15.5, 19.5
THETAS = [-62, -32, -2, 28, 118, 148, 178, 208]
L1, B1 = 13.5, -38.0
L2, B2 = 15.5, 26.0
W = (4.4, 3.0, 1.5)  # half-widths x2: root, knee, tip


def unit(a_deg):
    a = np.radians(a_deg)
    return np.array([np.cos(a), np.sin(a)])


def perp(u):
    return np.array([-u[1], u[0]])


def body_pt(theta):
    a = np.radians(theta)
    return C + np.array([RX * np.cos(a), RY * np.sin(a)])


def leg(theta, w, i1, i2, i3):
    base = body_pt(theta)
    tang = unit(theta + 90.0)  # increasing theta direction
    r1 = base - (w[0] / 2) * tang
    r2 = base + (w[0] / 2) * tang
    u1 = unit(theta + i1)
    knee = base + L1 * u1
    u2 = unit(theta + i1 + i2)
    tip = knee + L2 * u2
    k1 = knee - (w[1] / 2) * perp(u1)
    k2 = knee + (w[1] / 2) * perp(u1)
    if np.dot(k1 - knee, r1 - knee) < np.dot(k2 - knee, r1 - knee):
        k1, k2 = k2, k1
    t1 = tip - (w[2] / 2) * perp(u2)
    t2 = tip + (w[2] / 2) * perp(u2)
    if np.dot(t1 - tip, k1 - tip) < np.dot(t2 - tip, k1 - tip):
        t1, t2 = t2, t1
    return [r1, k1, t1, t2, k2, r2]


def build(w=W, l1=L1, b1=B1, l2=L2, b2=B2):
    pts = []
    for th in THETAS:
        pts += leg(th, w, b1, b2, 0)
    P = np.array(pts)
    # fit into the 0..100 box with a 6-unit margin
    lo, hi = P.min(axis=0), P.max(axis=0)
    span = float((hi - lo).max())
    if span > 88.0:
        P = (P - (lo + hi) / 2) * (88.0 / span) + 50.0
    lo, hi = P.min(axis=0), P.max(axis=0)
    P = P - (lo + hi) / 2 + 50.0
    return P


def report(name, P, out=None):
    ring = np.vstack([P, P[:1]])
    seg = np.linalg.norm(np.diff(ring, axis=0), axis=1)
    ls = LineString(ring)
    poly = Polygon(ring)
    ok_simple = ls.is_simple
    ok_bounds = bool((P >= 0).all() and (P <= 100).all())
    print(f"{name}: n={len(P)} min_gap={seg.min():.2f} simple={ok_simple} "
          f"bounds={ok_bounds} area={poly.area:.1f} "
          f"bbox=[{P[:,0].min():.1f},{P[:,1].min():.1f}]-[{P[:,0].max():.1f},{P[:,1].max():.1f}]")
    if out:
        json.dump({"dots": [[round(float(x), 2), round(float(y), 2)] for x, y in P]},
                  open(out, "w"), indent=1)
    return ok_simple and ok_bounds and seg.min() >= 0.5


if __name__ == "__main__":
    w = tuple(float(x) for x in sys.argv[1].split(",")) if len(sys.argv) > 1 else W
    name = sys.argv[2] if len(sys.argv) > 2 else "spider-slim"
    P = build(w=w)
    good = report(name, P, out=f"/opt/workspace/tmp/fourier-svg/spider-slim/{name}-dots.json")
    raise SystemExit(0 if good else 1)
