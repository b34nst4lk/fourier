import json, math, sys
sys.path.insert(0, "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts")

def load(name):
    d = json.load(open(name))
    d = d["dots"] if isinstance(d, dict) else d
    return [(float(p[0]), float(p[1])) for p in d]

def ang(a, b):
    return math.degrees(math.atan2(-(b[1]-a[1]), b[0]-a[0]))

def mid(p, q):
    return ((p[0]+q[0])/2, (p[1]+q[1])/2)

def side(P, sh, apex, root, tip, sgn):
    rake = ang(sh, apex) if sgn > 0 else 180 - ang(sh, apex)
    fb = math.degrees(math.atan2(tip[0]-root[0], -(tip[1]-root[1])))
    a1 = ang(root, tip); a2 = ang(sh, apex)
    fork = abs((a1 - a2 + 180) % 360 - 180)
    return dict(rake=rake, fork=fork, finger=fb,
                twig=math.dist(root, tip), arm=math.dist(sh, apex))

for name in ("asym2-B-dots.json", "snowman-asym-dots.json", "snowman-branch-dots.json"):
    P = load(name)
    shL = mid(P[9], P[20]); shR = mid(P[32], P[43])
    L = side(P, shL, P[13], P[15], P[17], +1)
    R = side(P, shR, P[39], P[37], P[35], -1)
    print(name)
    for k in ("rake", "fork", "finger", "twig", "arm"):
        print("  %-6s L %6.1f   R %6.1f   |d| %5.1f" % (k, L[k], R[k], abs(L[k]-R[k])))
