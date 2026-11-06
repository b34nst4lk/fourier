#!/usr/bin/env python3
"""Index the limbs of a traced ring: which node indices form each limb.

Reads a dots JSON (either [[x,y],...] or {"dots": [[x,y],...]}), computes the
body centroid, flags points that sit beyond `ratio` x the median of the smallest
half of the radii, and groups contiguous flagged runs into limbs. For each limb
prints the node range (1-based, inclusive), tip midpoint, outward bearing from
the centroid and limb length, so a review request can be phrased as
"shorten legs 7 and 8" instead of "node 34".

Usage:
    python3 limb_index.py DOTS.json [--ratio 1.45] [--json]
"""
import argparse
import json
import math
import sys


def load_dots(path):
    with open(path) as fh:
        data = json.load(fh)
    if isinstance(data, dict):
        for key in ("dots", "points", "polygon"):
            if key in data:
                data = data[key]
                break
        else:
            raise SystemExit(f"{path}: dict has no dots/points/polygon key")
    pts = [[float(p[0]), float(p[1])] for p in data]
    if len(pts) < 3:
        raise SystemExit(f"{path}: needs >= 3 points, got {len(pts)}")
    return pts


def limb_index(pts, ratio=1.45):
    n = len(pts)
    cx = sum(p[0] for p in pts) / n
    cy = sum(p[1] for p in pts) / n
    radii = [math.hypot(p[0] - cx, p[1] - cy) for p in pts]
    inner = sorted(radii)[: max(1, n // 2)]
    med = inner[len(inner) // 2]
    thresh = ratio * med
    far = [r > thresh for r in radii]

    limbs = []
    i = 0
    while i < n:
        if far[i]:
            j = i
            while j < n and far[j]:
                j += 1
            limbs.append((i, j - 1))
            i = j
        else:
            i += 1

    # a run that wraps the seam (index 0) is one limb, not two
    if len(limbs) >= 2 and limbs[0][0] == 0 and limbs[-1][1] == n - 1:
        first = limbs.pop(0)
        last = limbs.pop()
        limbs.append((last[0], n + first[1]))

    out = []
    for k, (a, b) in enumerate(limbs, 1):
        idx = [i % n for i in range(a, b + 1)]
        tx = sum(pts[i][0] for i in idx) / len(idx)
        ty = sum(pts[i][1] for i in idx) / len(idx)
        out.append({
            "limb": k,
            "nodes": f"{idx[0] + 1}-{idx[-1] + 1}",
            "node_indices": [i + 1 for i in idx],
            "tip": [round(tx, 1), round(ty, 1)],
            "bearing_deg": round(math.degrees(math.atan2(ty - cy, tx - cx))),
            "length": round(math.hypot(tx - cx, ty - cy), 1),
        })
    return {"centroid": [round(cx, 1), round(cy, 1)], "threshold": round(thresh, 2),
            "n": n, "limbs": out}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("dots")
    ap.add_argument("--ratio", type=float, default=1.45,
                    help="radius multiple of the inner median that marks a limb point (default 1.45)")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of text")
    args = ap.parse_args(argv)

    info = limb_index(load_dots(args.dots), args.ratio)
    if args.json:
        print(json.dumps(info, indent=2))
        return 0

    print(f"n={info['n']}  body centroid={tuple(info['centroid'])}  "
          f"limb threshold={info['threshold']}")
    lengths = [l["length"] for l in info["limbs"]]
    mean_len = (sum(lengths) / len(lengths)) if lengths else 0.0
    for l in info["limbs"]:
        flag = "  <-- >10% longer than the mean" if mean_len and l["length"] > 1.10 * mean_len else ""
        print(f"limb {l['limb']}: nodes {l['nodes']:<7} "
              f"tip=({l['tip'][0]:.1f}, {l['tip'][1]:.1f}) "
              f"dir={l['bearing_deg']:+d}deg  len={l['length']:.1f}{flag}")
    print(f"{len(info['limbs'])} limbs found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
