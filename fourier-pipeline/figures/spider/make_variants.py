#!/usr/bin/env python3
"""Generate anatomy variants of the slim spider (same 48-node budget)."""
import numpy as np

import build_spider as B

V = [
    ("spA", (15.5, 19.5), [-62, -32, -2, 28, 118, 148, 178, 208], 13.5, -38, 15.5, 26, (4.4, 3.0, 1.5)),
    ("spB", (14.0, 17.0), [-65, -35, -5, 25, 115, 145, 175, 205], 15.0, -45, 18.0, 75, (4.4, 2.8, 1.4)),
    ("spC", (14.0, 17.5), [-70, -40, -10, 20, 110, 140, 170, 200], 14.0, -28, 20.0, 58, (4.6, 3.0, 1.3)),
    ("spD", (15.0, 18.0), [-60, -30, 0, 30, 120, 150, 180, 210], 16.0, -52, 20.0, 62, (4.2, 2.6, 1.2)),
]

for name, (rx, ry), th, l1, b1, l2, b2, w in V:
    B.RX, B.RY = rx, ry
    B.THETAS = th
    P = B.build(w=w, l1=l1, b1=b1, l2=l2, b2=b2)
    B.report(name, P, out=f"/opt/workspace/tmp/fourier-svg/spider-slim/{name}-dots.json")
