"""Snowman v4: asymmetric twig arms.

v3 mirrored one arm (theta=40, twig 48 deg) onto the other side -- a defect
now, since a real snowman's arms are never mirror images.  v4 builds each
arm in its own frame so that:

  * the body-side angle differs   (left steeper than right)
  * the twig angle differs        (right twig opens wider)
  * the twig sits at a different fraction of the shaft and is a different
    length, so the two forks are not congruent

The single closed loop is preserved by emitting the right arm reversed
(mirroring is gone; frame rotation preserves traversal handedness, and the
loop runs M2R -> arm -> M1R, i.e. the opposite way along the same path).
"""
import json
import numpy as np
import make_branch2 as mb

SPLIT = 0.16
mb.M1 = mb.K[mb.KL] + SPLIT * (mb.K[mb.KL - 1] - mb.K[mb.KL])
mb.M2 = mb.K[mb.KL] + SPLIT * (mb.K[mb.KL + 1] - mb.K[mb.KL])
mb.M1R = mb.K[mb.KR] + SPLIT * (mb.K[mb.KR + 1] - mb.K[mb.KR])
mb.M2R = mb.K[mb.KR] + SPLIT * (mb.K[mb.KR - 1] - mb.K[mb.KR])


def arm_pts(O, u, up, L, at, twig_len, twig_deg, w0=1.55, taper=0.45,
            bend=0.09, wtwig=0.40, base=0.11):
    """One arm as a path from the mouth's first node round to its second.

    u   unit vector along the shaft (away from the body)
    up  unit normal pointing at the arm's upper edge (the side the twig grows
        from).  The twig base Q->Qb lies ON that edge and is skipped, so the
        path never crosses itself:  Q -> outer bulge -> tip -> Qb.
    """
    def C(s):
        return O + L * (s * u + bend * s * s * up)

    def w(s):
        return max(0.30, w0 * (1 - taper * s))

    Q = C(at) + w(at) * up
    Qb = C(at - base) + w(at - base) * up
    # Rotate inside the arm's own (u, up) frame so the twig opens *upward* on
    # both sides: up is rot(u,+90) on the left and rot(u,-90) on the right, so
    # a plain rot(u, deg) would send the right twig down through the shaft.
    a = np.radians(twig_deg)
    ut = np.cos(a) * u + np.sin(a) * up
    nt = -np.sin(a) * u + np.cos(a) * up
    Lt = twig_len * L
    wt = w(at) * wtwig
    return [
        C(0.26) - w(0.26) * up,
        C(at) - w(at) * up,
        C(0.88) - w(0.88) * up,
        C(1.0),
        C(0.88) + w(0.88) * up,
        Q,
        Q + 0.50 * Lt * ut + wt * nt,
        Q + Lt * ut,
        Qb,
        C(0.24) + w(0.24) * up,
    ]


def frame(side, theta):
    """Shaft direction + upper normal for a side ('L' or 'R')."""
    th = np.radians(theta)
    if side == "L":
        u = np.array([-np.cos(th), -np.sin(th)])
        up = np.array([-u[1], u[0]])          # up-and-right
    else:
        u = np.array([np.cos(th), -np.sin(th)])
        up = np.array([u[1], -u[0]])          # up-and-left
    return u, up


def build(LK, RK):
    O = (mb.M1 + mb.M2) / 2
    OR = (mb.M1R + mb.M2R) / 2
    lk = {k: v for k, v in LK.items() if k != "theta"}
    rk = {k: v for k, v in RK.items() if k != "theta"}
    uL, upL = frame("L", LK["theta"])
    uR, upR = frame("R", RK["theta"])
    a = [np.array(p) for p in arm_pts(O, uL, upL, **lk)]
    b = [np.array(p) for p in arm_pts(OR, uR, upR, **rk)][::-1]
    return ([p.tolist() for p in mb.K[:mb.KL]] + [mb.M1.tolist()]
            + [p.tolist() for p in a] + [mb.M2.tolist()]
            + [p.tolist() for p in mb.K[mb.KL + 1:mb.KR]] + [mb.M2R.tolist()]
            + [p.tolist() for p in b] + [mb.M1R.tolist()]
            + [p.tolist() for p in mb.K[mb.KR + 1:]])


# three asymmetry levels: body angle gap / twig angle gap
LEVELS = {
    "A-mild":   (dict(theta=40.0, at=0.56, twig_len=0.38, twig_deg=48.0, L=22.0),
                 dict(theta=36.0, at=0.60, twig_len=0.36, twig_deg=53.0, L=21.5)),
    "B-medium": (dict(theta=42.0, at=0.54, twig_len=0.40, twig_deg=44.0, L=22.0),
                 dict(theta=33.0, at=0.62, twig_len=0.38, twig_deg=58.0, L=21.0)),
    "C-bold":   (dict(theta=45.0, at=0.52, twig_len=0.42, twig_deg=40.0, L=22.0),
                 dict(theta=29.0, at=0.66, twig_len=0.40, twig_deg=64.0, L=20.5)),
}

if __name__ == "__main__":
    for name, (lk, rk) in LEVELS.items():
        dots = build(lk, rk)
        r = mb.check(dots, name, verbose=True)
        if r["hits"] == 0 and r["min_adj"] >= 0.5:
            json.dump(dots, open(f"asym-{name}-dots.json", "w"))
