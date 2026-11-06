#!/usr/bin/env python3
"""Render + validate a Fourier-puzzle silhouette polygon, optionally POST as draft.

Usage:
  python3 validate_puzzle.py --dots "50,12 52,18 58,16 ..." [--name butterfly] [--post]

The --dots arg is a space-separated list of x,y pairs (a closed loop; head/tail
single points). With --post it sends to the toy API as a draft.
"""
import math, json, pathlib, sys, urllib.request, argparse


def render(pts, cols=46, rows=22):
    g = [[" "] * cols for _ in range(rows)]
    sx = lambda x: round(x / 100 * (cols - 1))
    sy = lambda y: round(y / 100 * (rows - 1))
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        steps = max(abs(sx(x1) - sx(x0)), abs(sy(y1) - sy(y0)), 1)
        for s in range(steps + 1):
            t = s / steps
            gx = min(cols - 1, max(0, round(sx(x0) + (sx(x1) - sx(x0)) * t)))
            gy = min(rows - 1, max(0, round(sy(y0) + (sy(y1) - sy(y0)) * t)))
            g[gy][gx] = "#"
    return "\n".join("".join(r) for r in g)


def seg_int(p1, p2, p3, p4):
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])
    def on(a, b, c):
        return min(a[0], b[0]) <= c[0] <= max(a[0], b[0]) and min(a[1], b[1]) <= c[1] <= max(a[1], b[1])
    d1, d2 = ccw(p3, p4, p1), ccw(p3, p4, p2)
    d3, d4 = ccw(p1, p2, p3), ccw(p1, p2, p4)
    if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)):
        return True
    return (d1 == 0 and on(p3, p4, p1)) or (d2 == 0 and on(p3, p4, p2)) or \
           (d3 == 0 and on(p1, p2, p3)) or (d4 == 0 and on(p1, p2, p4))


def validate(pts):
    errs = []
    if len(pts) < 3:
        errs.append(f"too few dots: {len(pts)}")
    if not (12 <= len(pts) <= 50):
        errs.append(f"dot count {len(pts)} outside 12-50")
    if any(not (0 <= x <= 100 and 0 <= y <= 100) for x, y in pts):
        errs.append("dot out of bounds")
    md = min(math.dist(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts)))
    if md < 0.5:
        errs.append(f"min adjacent dist {round(md, 2)} < 0.5")
    n = len(pts)
    inter = []
    for i in range(n):
        for j in range(i + 1, n):
            if j == i + 1 or (i == 0 and j == n - 1):
                continue
            if seg_int(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]):
                inter.append((i, j))
    if inter:
        errs.append(f"self-intersections {inter}")
    return errs, md


def post(pts, name):
    key = ""
    for l in pathlib.Path("/opt/data/.env").read_text().splitlines():
        if l.startswith("FOURIER_AGENT_KEY="):
            key = l.split("=", 1)[1].strip()
    if not key:
        return {"error": "FOURIER_AGENT_KEY not found in /opt/data/.env"}
    body = json.dumps({"name": name, "dots": pts}).encode()
    req = urllib.request.Request(
        "http://toy_admin:8080/api/agent/puzzle", data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=10))
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}", "body": e.read().decode()[:300]}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dots", required=True, help='space-separated "x,y" pairs')
    ap.add_argument("--name", default="draft")
    ap.add_argument("--post", action="store_true")
    a = ap.parse_args()
    pts = [[round(float(v.split(",")[0]), 1), round(float(v.split(",")[1]), 1)]
           for v in a.dots.split()]
    print(render(pts))
    errs, md = validate(pts)
    print(f"\nVERIFY: dots={len(pts)}  min-adj={round(md, 2)}")
    if errs:
        print("FAIL:")
        for e in errs:
            print("  -", e)
        sys.exit(1)
    print("  intersections=none  in-bounds=OK")
    if a.post:
        res = post(pts, a.name)
        print("\nPOST RESPONSE:", json.dumps(res))
        if "error" in res:
            sys.exit(1)  # a failed POST must not exit 0, or callers will "verify" the wrong row
