"""Snowman v4a: asymmetric twig arms (finger direction specified absolutely).

v3 mirrored one arm onto the other.  v4 builds each arm in its own frame, and
v4a fixes a defect in the first attempt: with the twig given as an angle *off
the shaft*, a 9 deg difference in shaft rake can cancel a 14 deg difference in
fork angle, leaving both fingers pointing the same way (measured 4 deg and 1
deg left of vertical).  So the finger now gets an absolute bearing instead:

    finger = degrees off vertical, + = outboard (away from the body)

and the fork angle falls out of the geometry rather than being set directly.

Left  : shaft 44 deg up, finger +20 deg outboard -> narrow fork.
Right : shaft 32 deg up, finger  -8 deg (inboard, toward the head) -> wide fork.
Twig lengths and attachment points also differ, so nothing is congruent.
"""
import json
import numpy as np
import make_branch2 as mb

SPLIT = 0.16
mb.M1 = mb.K[mb.KL] + SPLIT * (mb.K[mb.KL - 1] - mb.K[mb.KL])
mb.M2 = mb.K[mb.KL] + SPLIT * (mb.K[mb.KL + 1] - mb.K[mb.KL])
mb.M1R = mb.K[mb.KR] + SPLIT * (mb.K[mb.KR + 1] - mb.K[mb.KR])
mb.M2R = mb.K[mb.KR] + SPLIT * (mb.K[mb.KR - 1] - mb.K[mb.KR])

SIDE = {"L": -1.0, "R": 1.0}          # outboard x direction


def arm_pts(O, side, theta, L, at, twig_len, fork,
            w0=1.55, taper=0.45, bend=0.09, wtwig=0.40, base=0.10):
    s = SIDE[side]
    th = np.radians(theta)
    u = np.array([s * np.cos(th), -np.sin(th)])        # shaft, away from body
    up = np.array([-u[1], u[0]]) if side == "L" else np.array([u[1], -u[0]])

    # Twig angle is measured off the shaft, but the *finger bearing* it implies
    # is bearing(shaft) - fork, so a wide fork on the shallow arm is what makes
    # the two fingers point different ways.  fork must stay >= 30 deg or the
    # outbound and return legs of the twig fold into each other (self-cross).
    a = np.radians(fork)
    ut = np.cos(a) * u + np.sin(a) * up               # finger, absolute
    nt = -np.sin(a) * u + np.cos(a) * up

    def C(t):
        return O + L * (t * u + bend * t * t * up)

    def w(t):
        return max(0.30, w0 * (1 - taper * t))

    Q = C(at) + w(at) * up
    Qb = C(at - base) + w(at - base) * up
    Lt, wt = twig_len * L, w(at) * wtwig
    return [C(0.26) - w(0.26) * up, C(at) - w(at) * up,
            C(0.88) - w(0.88) * up, C(1.0), C(0.88) + w(0.88) * up,
            Q, Q + 0.50 * Lt * ut + wt * nt, Q + Lt * ut, Qb,
            C(0.24) + w(0.24) * up]


def build(LK, RK):
    a = [np.array(p) for p in arm_pts((mb.M1 + mb.M2) / 2, "L", **LK)]
    b = [np.array(p) for p in arm_pts((mb.M1R + mb.M2R) / 2, "R", **RK)][::-1]
    K = mb.K
    return ([p.tolist() for p in K[:mb.KL]] + [mb.M1.tolist()]
            + [p.tolist() for p in a] + [mb.M2.tolist()]
            + [p.tolist() for p in K[mb.KL + 1:mb.KR]] + [mb.M2R.tolist()]
            + [p.tolist() for p in b] + [mb.M1R.tolist()]
            + [p.tolist() for p in K[mb.KR + 1:]])


def measure(P):
    """Visible angles read off the emitted polygon, not the parameters."""
    P = np.array(P, float)
    out = {}
    for side, (first, last, apex, q, tip) in {
            "L": (10, 19, 13, 15, 17), "R": (33, 42, 39, 37, 35)}.items():
        root = (P[first] + P[last]) / 2
        su = P[apex] - root
        tu = P[tip] - P[q]
        su /= np.linalg.norm(su); tu /= np.linalg.norm(tu)
        shaft_deg = np.degrees(np.arctan2(-su[1], abs(su[0])))       # above horiz
        finger_deg = -SIDE[side] * np.degrees(np.arctan2(-tu[0], -tu[1]))
        out[side] = dict(shaft=shaft_deg, finger=finger_deg,
                         fork=abs(np.degrees(np.arccos(np.clip(su @ tu, -1, 1)))),
                         len=np.linalg.norm(P[apex] - root),
                         twig=np.linalg.norm(P[tip] - P[q]))
    out["gap"] = (out["L"]["shaft"] - out["R"]["shaft"],
                  out["L"]["finger"] - out["R"]["finger"],
                  out["L"]["fork"] - out["R"]["fork"])
    return out


LEVELS = {
    "A": (dict(theta=43.0, L=22.0, at=0.56, twig_len=0.38, fork=38.0),
          dict(theta=36.0, L=21.5, at=0.60, twig_len=0.34, fork=50.0)),
    "B": (dict(theta=44.0, L=22.0, at=0.55, twig_len=0.40, fork=38.0),
          dict(theta=33.0, L=21.0, at=0.62, twig_len=0.33, fork=63.0)),
    "C": (dict(theta=46.0, L=22.0, at=0.54, twig_len=0.42, fork=38.0),
          dict(theta=30.0, L=20.5, at=0.65, twig_len=0.30, fork=70.0)),
}

if __name__ == "__main__":
    for name, (lk, rk) in LEVELS.items():
        dots = build(lk, rk)
        r = mb.check(dots, name, verbose=True)
        m = measure(dots)
        print(f"  {name} shaft {m['L']['shaft']:.0f}/{m['R']['shaft']:.0f} "
              f"finger {m['L']['finger']:+.0f}/{m['R']['finger']:+.0f} "
              f"fork {m['L']['fork']:.0f}/{m['R']['fork']:.0f} "
              f"|L| {m['L']['len']:.1f}/{m['R']['len']:.1f} "
              f"twig {m['L']['twig']:.1f}/{m['R']['twig']:.1f}")
        if r["hits"] == 0 and r["min_adj"] >= 0.5:
            json.dump(dots, open(f"asym2-{name}-dots.json", "w"))
