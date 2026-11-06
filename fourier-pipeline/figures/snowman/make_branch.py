"""Snowman arms as tapered forking twigs (v3) -- replaces the v2 paddles.

Why v2 failed: each v2 arm was spliced across the whole left flank (mouth
20.8 units wide, y=55.4 up to y=34.6), so the "arm" was a 24-unit paddle with
three short spikes.  Each arm carried ~16% of the body's area.

v3 rule (Leonardo's rule, D_parent^2 = sum D_daughter^2, exponent 1.8-2.3):
a fork into two equal daughters gives d = D/sqrt(2) = 0.71D, so the shaft
tapers linearly and steps down once at the fork.  One fork only -- two forks
read as antlers, not branches.

Arm node order (left arm, 9 nodes between the two new mouth nodes M1, M2):
  M1 -> bottom edge -> apex -> top edge -> fork base (far, on edge)
  -> stub tip -> fork base (near, on edge) -> top edge -> M2
The shaft edge between the two fork bases is skipped: that notch is the fork.
"""
import json
import numpy as np

SRC = "/opt/workspace/tmp/fourier-svg/violin-snowman/snowman-v2-dots.json"
P0 = [np.array(p, float) for p in json.load(open(SRC))]
K = [p for i, p in enumerate(P0) if not (10 <= i <= 19 or 31 <= i <= 40)]
KL, KR = 9, 21
M1 = K[KL] + 0.27 * (K[KL - 1] - K[KL])
M2 = K[KL] + 0.27 * (K[KL + 1] - K[KL])
M1R = K[KR] + 0.27 * (K[KR + 1] - K[KR])
M2R = K[KR] + 0.27 * (K[KR - 1] - K[KR])
MOUTH = np.linalg.norm(M2 - M1)


def seg_int(a, b, c, d):
    def cr(o, p, q):
        return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])
    return cr(c, d, a) * cr(c, d, b) < 0 and cr(a, b, c) * cr(a, b, d) < 0


def check(P, name="", quiet=False, verbose=False):
    P = np.array(P, float)
    n = len(P)
    Q = np.vstack([P, P[:1]])
    segs = [(Q[i], Q[i + 1]) for i in range(n)]
    gaps = [float(np.linalg.norm(P[(i + 1) % n] - P[i])) for i in range(n)]
    bad = [(i + 1, j + 1) for i in range(n) for j in range(i + 2, n)
           if not (i == 0 and j == n - 1) and seg_int(segs[i][0], segs[i][1], segs[j][0], segs[j][1])]
    area = 0.5 * abs(np.dot(P[:, 0], np.roll(P[:, 1], -1)) - np.dot(P[:, 1], np.roll(P[:, 0], -1)))
    row = (f"{name:>5} n={n:2d} min_adj={min(gaps):4.2f} self_int={len(bad)} area={area:6.1f} "
           f"bbox=[{P[:,0].min():5.1f},{P[:,1].min():5.1f}]-[{P[:,0].max():5.1f},{P[:,1].max():5.1f}] "
           f"w={P[:,0].max()-P[:,0].min():4.1f}")
    if not quiet:
        print(row, ("pairs=" + str(bad)) if (bad and verbose) else "")
    return dict(n=n, min_adj=min(gaps), hits=len(bad), area=area, pairs=bad,
                w=float(P[:, 0].max() - P[:, 0].min()), row=row)


def arm(L, theta_deg, half_root, fork_at, fork_angle, fork_len, bend=0.05, taper=0.55):
    th = np.radians(theta_deg)
    u = np.array([-np.cos(th), -np.sin(th)])
    n = np.array([-u[1], u[0]])                      # up/right side of the shaft
    O = (M1 + M2) / 2

    def C(s):
        return O + L * (s * u + bend * s * s * n)

    def W(s):
        return max(0.34, half_root * (1 - taper * s))

    def E(s):                                       # point on the top/shaft edge
        return C(s) + W(s) * n

    if fork_at is None:
        return [C(0.07) - W(0.07) * n, C(0.52) - W(0.52) * n, C(1.0),
                C(0.88) + W(0.88) * n, C(0.55) + W(0.55) * n, C(0.07) + W(0.07) * n]

    fa = np.radians(fork_angle)
    fu = np.cos(fa) * u + np.sin(fa) * n
    sf, sn = fork_at, fork_at - 0.115
    base_far, base_near = E(sf), E(sn)
    mid = (base_far + base_near) / 2
    return [
        C(0.10) - W(0.10) * n,                      # 1 bottom edge, root
        C(0.56) - W(0.56) * n,                      # 2 bottom edge, mid
        C(1.0),                                     # 3 apex, sharp twig tip
        C(0.88) + W(0.88) * n,                      # 4 top edge below apex
        base_far,                                   # 5 fork base, tip side
        mid + fork_len * fu,                        # 6 fork tip
        base_near,                                  # 7 fork base, body side
        C(0.30) + W(0.30) * n,                      # 8 top edge, above body
        C(0.08) + W(0.08) * n,                      # 9 top edge, at body
    ]


def build(L, theta, half_root, fork_at, fork_angle, fork_len, bend=0.05):
    a = [np.array(p) for p in arm(L, theta, half_root, fork_at, fork_angle, fork_len, bend)]
    m = [np.array([100 - p[0], p[1]]) for p in a]
    return ([p.tolist() for p in K[:KL]] + [M1.tolist()] + [p.tolist() for p in a]
            + [M2.tolist()] + [p.tolist() for p in K[KL + 1:KR]] + [M2R.tolist()]
            + [p.tolist() for p in m[::-1]] + [M1R.tolist()] + [p.tolist() for p in K[KR + 1:]])


VARIANTS = {
    "brA": dict(L=15.0, theta=30, half_root=1.45, fork_at=0.58, fork_angle=40, fork_len=6.0),
    "brB": dict(L=17.5, theta=34, half_root=1.45, fork_at=0.55, fork_angle=42, fork_len=7.2),
    "brC": dict(L=20.0, theta=38, half_root=1.45, fork_at=0.52, fork_angle=45, fork_len=8.6),
    "brD": dict(L=17.5, theta=34, half_root=1.45, fork_at=None, fork_angle=42, fork_len=0),
}

if __name__ == "__main__":
    print(f"mouth={MOUTH:.2f}")
    for name, kw in VARIANTS.items():
        dots = build(**kw)
        r = check(dots, name, verbose=True)
        if r["hits"] == 0 and r["min_adj"] >= 0.5:
            json.dump(dots, open(f"{name}-dots.json", "w"))
