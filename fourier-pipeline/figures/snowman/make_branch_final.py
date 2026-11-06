"""Final snowman v3 arm: side twig on a tapered shaft.

Geometry (all units on the toy's 0-100 grid, y down):
  shaft: root half-width 1.55 -> 0.30, tapered, bowed slightly upward
  mouth: 3.33 wide (was 20.8 in v2)
  length 22 at 38-40 deg above horizontal (0.49 x body height)
  twig: leaves the upper edge at 56% of the shaft, 8.4 long, 48 deg,
        half-width ~0.6 at the base
  46 nodes total (24 body + 2 mouth + 10 per arm)
"""
import json
import numpy as np
import make_branch2 as mb

SPLIT = 0.16
mb.M1 = mb.K[mb.KL] + SPLIT * (mb.K[mb.KL - 1] - mb.K[mb.KL])
mb.M2 = mb.K[mb.KL] + SPLIT * (mb.K[mb.KL + 1] - mb.K[mb.KL])
mb.M1R = mb.K[mb.KR] + SPLIT * (mb.K[mb.KR + 1] - mb.K[mb.KR])
mb.M2R = mb.K[mb.KR] + SPLIT * (mb.K[mb.KR - 1] - mb.K[mb.KR])

KW = dict(L=22.0, theta=40, at=0.56, twig_len=0.38, twig_deg=48.0, base=0.11, wtwig=0.40)

dots = mb.build(armfn=mb.arm_side, **KW)
r = mb.check(dots, "snowman-branch", verbose=True)
assert r["hits"] == 0 and r["min_adj"] >= 0.5
json.dump(dots, open("snowman-branch-dots.json", "w"))
print("wrote snowman-branch-dots.json")
