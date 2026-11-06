"""Snowman arms as forking twigs (v3, topology B: shaft ENDS at the fork).

v2 defect: each arm was a 24-unit paddle (mouth 20.8 wide) with three short
spikes -- 16% of body area per arm, span 67 units.

v3 rule: Leonardo's rule (D_parent^2 = sum D_daughter^2, exponent 1.8-2.3)
=> a fork into two equal daughters gives d = 0.71 D, so the shaft steps down
once at the fork.  One fork only; two forks read as antlers.

v3 topology B: the shaft terminates at the fork point and splits into two
prongs (main continues the axis, daughter leaves at fork_angle).  The notch
between them is a true V reaching the fork point, so it reads as a Y, not as
a barb on a continuing shaft.

  M1 -> shaft lower -> fork lower -> main lower -> main tip -> main upper
  -> notch (fork point) -> daughter lower -> daughter tip -> daughter upper
  -> shaft upper -> M2
"""
import json
import numpy as np

SRC = "/opt/workspace/tmp/fourier-svg/violin-snowman/snowman-v2-dots.json"
P0 = [np.array(p, float) for p in json.load(open(SRC))]
K = [p for i, p in enumerate(P0) if not (10 <= i <= 19 or 31 <= i <= 40)]
KL, KR = 9, 21
SPLIT = 0.27
M1 = K[KL] + SPLIT * (K[KL - 1] - K[KL])
M2 = K[KL] + SPLIT * (K[KL + 1] - K[KL])
M1R = K[KR] + SPLIT * (K[KR + 1] - K[KR])
M2R = K[KR] + SPLIT * (K[KR - 1] - K[KR])
MOUTH = float(np.linalg.norm(M2 - M1))


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
    row = (f"{name:>5} n={n:2d} min_adj={min(gaps):4.2f} int={len(bad)} area={area:6.1f} "
           f"bbox=[{P[:,0].min():5.1f},{P[:,1].min():5.1f}]-[{P[:,0].max():5.1f},{P[:,1].max():5.1f}] "
           f"w={P[:,0].max()-P[:,0].min():4.1f}")
    if not quiet:
        print(row, ("pairs=" + str(bad)) if (bad and verbose) else "")
    return dict(n=n, min_adj=min(gaps), hits=len(bad), area=area, pairs=bad,
                w=float(P[:, 0].max() - P[:, 0].min()), bbox=[float(P[:,0].min()), float(P[:,1].min()),
                                                             float(P[:,0].max()), float(P[:,1].max())], row=row)


def rot(v, deg):
    t = np.radians(deg)
    c, s = np.cos(t), np.sin(t)
    return np.array([c * v[0] - s * v[1], s * v[0] + c * v[1]])


def arm(L=15.0, theta=22.0, w0=1.55, fork_s=0.55, main_deg=8.0, main_len=0.55,
        dang=36.0, dlen=0.42, bend=0.09, taper=0.45, wmain=0.62, wdaugh=0.50):
    """Left arm, 11 nodes between the mouth nodes M1 and M2."""
    th = np.radians(theta)
    u = np.array([-np.cos(th), -np.sin(th)])
    n = np.array([-u[1], u[0]])
    O = (M1 + M2) / 2

    def C(s):
        return O + L * (s * u + bend * s * s * n)

    def w(s):
        return max(0.30, w0 * (1 - taper * s))

    F = C(fork_s)                                  # fork point, on the axis
    um = rot(u, main_deg)
    ud = rot(u, dang)
    Lm, Ld = main_len * L, dlen * L
    wf = w(fork_s)
    return [
        C(0.26) - w(0.26) * n,                      # 1 shaft, lower edge
        C(fork_s) - wf * n,                        # 2 shaft, lower edge at fork
        F + 0.55 * Lm * um - wf * wmain * rot(n, main_deg),   # 3 main, lower edge
        F + Lm * um,                               # 4 main tip
        F + 0.55 * Lm * um + wf * wmain * 0.62 * rot(n, main_deg),  # 5 main, upper edge
        F,                                         # 6 notch apex = fork point
        F + 0.55 * Ld * ud - wf * wdaugh * rot(n, dang),       # 7 daughter, lower edge
        F + Ld * ud,                               # 8 daughter tip
        F + 0.55 * Ld * ud + wf * wdaugh * 0.62 * rot(n, dang),  # 9 daughter, upper edge
        C(fork_s) + wf * n,                        # 10 shaft, upper edge at fork
        C(0.24) + w(0.24) * n,                     # 11 shaft, upper edge
    ]


def build(armfn=None, **kw):
    a = [np.array(p) for p in (armfn or arm)(**kw)]
    m = [np.array([100 - p[0], p[1]]) for p in a]
    return ([p.tolist() for p in K[:KL]] + [M1.tolist()] + [p.tolist() for p in a]
            + [M2.tolist()] + [p.tolist() for p in K[KL + 1:KR]] + [M2R.tolist()]
            + [p.tolist() for p in m[::-1]] + [M1R.tolist()] + [p.tolist() for p in K[KR + 1:]])


VARIANTS = {
    "F1": dict(L=15.0, theta=22, fork_s=0.55, main_deg=8, main_len=0.55, dang=36, dlen=0.42),
    "F2": dict(L=14.0, theta=26, fork_s=0.55, main_deg=6, main_len=0.57, dang=40, dlen=0.46),
    "F3": dict(L=17.0, theta=18, fork_s=0.56, main_deg=10, main_len=0.53, dang=32, dlen=0.38),
    "F4": dict(L=16.0, theta=24, fork_s=0.52, main_deg=12, main_len=0.60, dang=44, dlen=0.47),
}

if __name__ == "__main__":
    print(f"mouth={MOUTH:.2f}")
    for name, kw in VARIANTS.items():
        dots = build(**kw)
        r = check(dots, name, verbose=True)
        if r["hits"] == 0 and r["min_adj"] >= 0.5:
            json.dump(dots, open(f"{name}-dots.json", "w"))


def arm_side(L=24.0, theta=40.0, w0=1.55, at=0.62, twig_len=0.30, twig_deg=45.0,
             bend=0.09, taper=0.45, wtwig=0.52, base=0.10):
    """Side-twig topology: the shaft runs on past the twig to its own tip and a
    single twig leaves the upper edge at `at` (fraction of L) at `twig_deg`.
    The twig is a wedge whose base lies ON the shaft edge (Q -> Qb, skipped),
    so nothing crosses: Q -> outer bulge -> twig tip -> Qb."""
    th = np.radians(theta)
    u = np.array([-np.cos(th), -np.sin(th)])
    n = np.array([-u[1], u[0]])
    O = (M1 + M2) / 2

    def C(s):
        return O + L * (s * u + bend * s * s * n)

    def w(s):
        return max(0.30, w0 * (1 - taper * s))

    Q = C(at) + w(at) * n
    Qb = C(at - base) + w(at - base) * n
    ut = rot(u, twig_deg)
    nt = rot(n, twig_deg)
    Lt = twig_len * L
    wt = w(at) * wtwig
    return [
        C(0.26) - w(0.26) * n,
        C(at) - w(at) * n,
        C(0.88) - w(0.88) * n,
        C(1.0),                               # shaft apex
        C(0.88) + w(0.88) * n,
        Q,                                    # twig root, on the shaft edge
        Q + 0.50 * Lt * ut + wt * nt,         # twig outer edge
        Q + Lt * ut,                          # twig tip
        Qb,                                   # twig base, on the shaft edge
        C(0.24) + w(0.24) * n,
    ]
