#!/usr/bin/env python3
"""Score a dot set the way toy_admin/derivation.gleam will: 512-pt arc-length
resample -> DFT -> top-4 by |c_k| are the dials, everything else frozen.

Reports IoU (what the player sees) and dial dominance (how cleanly the four
movable terms own the shape). Usage: python spectral.py duck bird
"""
import sys
import numpy as np
import shapely.geometry as sg
import svg_to_puzzle as S

N = 512


def resample_closed(dots, n=N):
    p = np.array(dots, dtype=float)
    p = np.vstack([p, p[:1]])
    seg = np.hypot(*np.diff(p, axis=0).T)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    total = cum[-1]
    t = np.linspace(0, total, n, endpoint=False)
    x = np.interp(t, cum, p[:, 0])
    y = np.interp(t, cum, p[:, 1])
    return np.stack([x, y], axis=1)


def spectrum(dots):
    s = resample_closed(dots)
    z = s[:, 0] + 1j * s[:, 1]
    c = np.fft.fft(z) / N
    k = np.fft.fftfreq(N, 1 / N).astype(int)
    keep = k != 0
    order = np.argsort(-np.abs(c[keep]), kind="stable")
    ks, cs = k[keep][order], c[keep][order]
    # derivation.gleam sorts by radius desc, ties by |k| asc
    ties = np.lexsort((np.abs(ks), -np.abs(cs)))
    ks, cs = ks[ties], cs[ties]
    return ks, cs, s


def report(name, n, dots, iou):
    ks, cs, s = spectrum(dots)
    amp = np.abs(cs)
    top4 = amp[:4].sum()
    tot = amp.sum()
    dom = amp[3] / amp[4] if len(amp) > 4 else float("inf")
    print(f"{name:<6} n={n:<3} IoU={iou:.3f} top4_k={list(ks[:4])} "
          f"amps={np.round(amp[:5], 2)} dial/extra c4:c5={dom:5.2f} "
          f"energy_top4={top4 / tot:.2%}")


if __name__ == "__main__":
    for name in sys.argv[1:]:
        outer, src, rows = S.curve(name)
        print(f"\n### {name}")
        for r in rows:
            if r["n"] in (12, 14, 16, 18, 20, 22, 24, 26, 28, 30) and r["ok"]:
                report(name, r["n"], r["dots"], r["iou"])
