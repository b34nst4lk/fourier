#!/usr/bin/env python3
"""SVG silhouette -> Fourier-toy puzzle dots.

    fetch   download candidate filled icons (MDI, Apache-2.0)
    sheet   contact sheet + subpath/area report -- look at it before choosing
    build   contour -> Douglas-Peucker sweep -> IoU + spectrum -> dots.json + preview.png

Why IoU is the honest score: toy_admin's stored "target" trace is a 512-point
arc-length resample of the closed polygon through the dots, i.e. straight edges.
So the player sees exactly this polygon; overlap with the source silhouette is
fidelity, not a proxy.

Why the preview PNG is the assessment: the validator's ASCII grid (~52x24) is a
second, much lossier rasterisation -- on `bird` it prints as a scribble. Render
the polygon and look at the image.

Env is self-bootstrapping: if the deps are missing the script re-execs into
<skill>/scripts/bootstrap.sh creates a venv once at /opt/data/cache/fourier-puzzle
"""
import argparse
import json
import math
import os
import pathlib
import sys
import urllib.request

SKILL_DIR = pathlib.Path(__file__).resolve().parents[1]
VENV_PY = pathlib.Path(os.environ.get("FOURIER_VENV", "/opt/data/cache/fourier-puzzle")) / "bin" / "python"
MDI = "https://unpkg.com/@mdi/svg@7.4.47/svg/{name}.svg"
MDI_ALT = "https://cdn.jsdelivr.net/npm/@mdi/svg@7.4.47/svg/{name}.svg"


def ensure_env():
    try:
        import matplotlib  # noqa: F401
        import numpy  # noqa: F401
        import shapely  # noqa: F401
        import svgpathtools  # noqa: F401
        return
    except ImportError:
        pass
    if VENV_PY.exists() and pathlib.Path(sys.executable) != VENV_PY:
        os.execv(str(VENV_PY), [str(VENV_PY), str(pathlib.Path(__file__).resolve())] + sys.argv[1:])
    sys.exit(
        "missing numpy/shapely/svgpathtools/matplotlib --\n"
        f"  bash {SKILL_DIR}/scripts/bootstrap.sh"
    )


ensure_env()

import numpy as np  # noqa: E402
import shapely.geometry as sg  # noqa: E402
from svgpathtools import svg2paths2  # noqa: E402
import matplotlib  # noqa: E402

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


# ---------------------------------------------------------------- geometry --
def contours(svg_path, samples=400):
    """All closed subpaths of an SVG, largest shoelace area first."""
    paths, _, _ = svg2paths2(str(svg_path))
    out = []
    for p in paths:
        for sub in p.continuous_subpaths():
            xy = np.array(
                [[sub.point(t / samples).real, sub.point(t / samples).imag] for t in range(samples + 1)]
            )
            if len(xy) >= 3:
                out.append({"xy": xy, "area": abs(sg.Polygon(xy).area)})
    out.sort(key=lambda d: -d["area"])
    return out


def classify(cs):
    """Label every subpath: outer, hole (inside the outer), or part (disjoint).

    A hole is safe to drop -- a closed loop cannot carry one. A DISJOINT PART is
    not: dropping it silently halves the drawing (a butterfly's second wing), and
    IoU against the largest contour cannot see the loss because it never scores
    the discarded geometry. Hence the hard refusal in build.
    """
    outer = sg.Polygon(cs[0]["xy"])
    labels = ["outer"]
    for c in cs[1:]:
        poly = sg.Polygon(c["xy"])
        labels.append("hole" if outer.contains(poly.representative_point()) else "part")
    return labels


def normalise(xy, margin=4.0):
    """Aspect-preserving fit into [margin, 100-margin]; y-down is kept as-is."""
    lo, hi = xy.min(axis=0), xy.max(axis=0)
    span = hi - lo
    scale = (100.0 - 2 * margin) / max(span[0], span[1])
    out = (xy - lo) * scale
    off = ((100.0 - 2 * margin) - span * scale) / 2.0
    return out + off + margin


def _rdp(points, eps):
    if len(points) < 3:
        return points
    a, b = points[0], points[-1]
    ab = b - a
    nrm = np.hypot(*ab)
    if nrm == 0:
        d = np.hypot(*(points - a).T)
    else:
        rel = points - a
        d = np.abs(ab[0] * rel[:, 1] - ab[1] * rel[:, 0]) / nrm  # numpy2: no np.cross on 2-D
    i = int(np.argmax(d))
    if d[i] > eps:
        return np.vstack([_rdp(points[: i + 1], eps)[:-1], _rdp(points[i:], eps)])
    return np.array([a, b])


def rdp_closed(xy, eps):
    pts = xy[:-1] if np.allclose(xy[0], xy[-1]) else xy
    i1 = int(np.argmax(np.hypot(*(pts - pts[0]).T)))
    a = _rdp(pts[: i1 + 1], eps)
    b = _rdp(np.vstack([pts[i1:], pts[:1]]), eps)
    return np.vstack([a[:-1], b[:-1]])


def at_count(xy, target, lo=0.05, hi=25.0):
    """Bisect the RDP epsilon until the vertex count lands on `target`."""
    best = None
    for _ in range(45):
        mid = (lo + hi) / 2
        out = rdp_closed(xy, mid)
        if best is None or abs(len(out) - target) < abs(len(best[1]) - target):
            best = (mid, out)
        if len(out) == target:
            break
        lo, hi = (mid, hi) if len(out) > target else (lo, mid)
    return best[1]


def seg_int(p1, p2, p3, p4):
    def ccw(a, b, c):
        return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])

    def on(a, b, c):
        return (
            min(a[0], b[0]) <= c[0] <= max(a[0], b[0])
            and min(a[1], b[1]) <= c[1] <= max(a[1], b[1])
        )

    d1, d2 = ccw(p3, p4, p1), ccw(p3, p4, p2)
    d3, d4 = ccw(p1, p2, p3), ccw(p1, p2, p4)
    if ((d1 > 0 > d2) or (d1 < 0 < d2)) and ((d3 > 0 > d4) or (d3 < 0 < d4)):
        return True
    return (
        (d1 == 0 and on(p3, p4, p1))
        or (d2 == 0 and on(p3, p4, p2))
        or (d3 == 0 and on(p1, p2, p3))
        or (d4 == 0 and on(p1, p2, p4))
    )


def validate(dots):
    """Structural rules: 12-50 dots, gap >= 0.5, in bounds, no self-intersection.

    Ceiling raised 30 -> 50 on 2026-10-29 (Jack) so shapes built from edge-cut
    pockets (eyes, slots) can spend vertices on detail without losing outline.
    """
    errs, n = [], len(dots)
    if not 12 <= n <= 50:
        errs.append(f"dot count {n} outside 12-50")
    if any(not (0 <= x <= 100 and 0 <= y <= 100) for x, y in dots):
        errs.append("dot out of bounds")
    md = min(math.dist(dots[i], dots[(i + 1) % n]) for i in range(n))
    if md < 0.5:
        errs.append(f"min adjacent dist {md:.2f} < 0.5")
    inter = [
        (i, j)
        for i in range(n)
        for j in range(i + 1, n)
        if not (j == i + 1 or (i == 0 and j == n - 1))
        and seg_int(dots[i], dots[(i + 1) % n], dots[j], dots[(j + 1) % n])
    ]
    if inter:
        errs.append(f"self-intersections {inter}")
    return errs, md


def iou(dots, source_poly):
    cand = sg.Polygon(dots)
    if not cand.is_valid:
        return 0.0
    union = cand.union(source_poly).area
    return cand.intersection(source_poly).area / union if union else 0.0


def spectrum(dots, n=512):
    """|c_k| of the 512-pt arc-length resample. derivation.gleam: k=0 is the
    centroid (DC, not a dial); the dials are the top 4 by |c_k| for k != 0."""
    p = np.vstack([np.asarray(dots, float), np.asarray(dots, float)[:1]])
    seg = np.hypot(*np.diff(p, axis=0).T)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    t = np.linspace(0, cum[-1], n, endpoint=False)
    z = np.interp(t, cum, p[:, 0]) + 1j * np.interp(t, cum, p[:, 1])
    c = np.fft.fft(z) / n
    ks = np.arange(n)
    ks = np.where(ks > n // 2, ks - n, ks)
    live = ks != 0  # DC carries the shape's position, never dialable
    order = np.argsort(-np.abs(c))
    amps = [(float(abs(c[k])), int(ks[k])) for k in order if live[k]][:6]
    ratio = amps[3][0] / amps[4][0] if amps[4][0] else float("inf")
    live_energy = float(np.sum(np.abs(c[live]) ** 2))
    share = float(sum(a ** 2 for a, _ in amps[:4]) / live_energy) if live_energy else 0.0
    return amps, ratio, share


# ----------------------------------------------------------------- preview --
def preview(name, outer, dots, meta, path):
    d = np.asarray(dots, float)
    ring = np.vstack([d, d[:1]])
    fig, (ax0, ax1) = plt.subplots(1, 2, figsize=(9.6, 4.9))

    ax0.fill(outer[:, 0], outer[:, 1], color="0.80", lw=0)
    ax0.plot(ring[:, 0], ring[:, 1], "-", color="black", lw=1.4)
    ax0.plot(d[:, 0], d[:, 1], "o", color="tab:red", ms=4)
    for i, (x, y) in enumerate(d):
        ax0.annotate(str(i), (x, y), fontsize=6, color="tab:red",
                     xytext=(2, -4), textcoords="offset points")
    ax0.set_title(f"source (grey) vs player-visible polygon (black) - {name}", fontsize=9)

    ax1.fill(ring[:, 0], ring[:, 1], color="none", ec="black", lw=2.2)
    ax1.set_title(
        f"n={meta['n']}  IoU={meta['iou']:.3f}  min_gap={meta['min_adj']:.2f}"
        f"  c4:c5={meta['ratio']:.2f}",
        fontsize=9,
    )
    for ax in (ax0, ax1):
        ax.set_xlim(-3, 103)
        ax.set_ylim(103, -3)  # y-down, as the store stores it
        ax.set_aspect("equal")
        ax.axis("off")
    plt.tight_layout()
    plt.savefig(path, dpi=130)
    plt.close()
    return path


# -------------------------------------------------------------- subcommands --
def cmd_fetch(a):
    out = pathlib.Path(a.dir)
    out.mkdir(parents=True, exist_ok=True)
    bad = []
    for name in a.names:
        dest = out / f"{name}.svg"
        for url in (MDI.format(name=name), MDI_ALT.format(name=name)):
            try:
                with urllib.request.urlopen(url, timeout=15) as r:
                    body = r.read()
                if b"<svg" in body:
                    dest.write_bytes(body)
                    print(f"  ok   {name:<12} {len(body):>6} bytes")
                    break
            except Exception:
                continue
        else:
            bad.append(name)
            print(f"  FAIL {name}")
    print(f"fetched {len(a.names) - len(bad)}/{len(a.names)} into {out}")
    if bad:
        print("not in MDI: " + ", ".join(bad))


def cmd_sheet(a):
    out = pathlib.Path(a.dir)
    files = sorted(out.glob("*.svg"))
    if not files:
        sys.exit(f"no .svg in {out} - run `fetch` first")
    keep = []
    print(f"{'icon':<14}{'subpaths':>9}  areas (largest first) + hole/part classification")
    for f in files:
        try:
            cs = contours(f)
        except Exception as e:  # malformed download
            print(f"{f.stem:<14}{'ERR':>9}  {e}")
            continue
        if not cs:
            continue
        areas = [round(c["area"], 1) for c in cs]
        labels = classify(cs)
        parts = labels.count("part")
        tag = f"  UNUSABLE: {parts} disjoint part(s), not holes" if parts else ""
        print(f"{f.stem:<14}{len(cs):>9}  {areas[:4]}  holes={labels.count('hole')} parts={parts}{tag}")
        keep.append((f.stem, cs))
    cols = 5
    rows = max(1, (len(keep) + cols - 1) // cols)
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 2.5, rows * 2.7))
    axes = np.atleast_2d(axes)
    for i, (n, cs) in enumerate(keep):
        ax = axes[i // cols][i % cols]
        for c in cs:
            xy = c["xy"]
            ax.fill(xy[:, 0], xy[:, 1], color="black" if c is cs[0] else "tab:orange", lw=0)
        ax.set_title(f"{n} ({len(cs)})", fontsize=9)
        ax.set_aspect("equal")
        ax.invert_yaxis()
        ax.axis("off")
    for j in range(len(keep), rows * cols):
        axes[j // cols][j % cols].axis("off")
    plt.tight_layout()
    path = out.parent / "contact.png"
    plt.savefig(path, dpi=110)
    plt.close()
    print(f"\nwrote {path}  (orange = dropped hole subpaths)")


def cmd_build(a):
    src_file = pathlib.Path(a.source)
    if not src_file.exists():
        src_file = pathlib.Path(a.dir) / f"{a.source}.svg"
    if not src_file.exists():
        sys.exit(f"no such svg: {a.source}")
    name = src_file.stem

    cs = contours(src_file)
    if not cs:
        sys.exit("no closed subpaths found")
    outer = normalise(cs[0]["xy"], a.margin)
    source_poly = sg.Polygon(outer)
    labels = classify(cs)
    holes, parts = labels.count("hole"), labels.count("part")
    print(f"{name}: {len(cs)} subpath(s), largest area {cs[0]['area']:.1f}, "
          f"{holes} hole(s), {parts} disjoint part(s)")
    if parts:
        sys.exit(
            "REFUSED: this silhouette is multi-part (disjoint subpaths), so one closed\n"
            "loop cannot represent it -- dropping the rest silently halves the drawing.\n"
            "Pick an icon that is a single connected silhouette, or union the parts\n"
            "first (they still must touch, or the loop would self-intersect)."
        )
    if holes:
        print("  hole(s) dropped: a closed loop cannot carry an interior hole")

    rows = []
    for target in range(12, a.max_dots + 1):
        arr = at_count(outer, target)
        dots = [[round(float(x), 2), round(float(y), 2)] for x, y in arr]
        errs, md = validate(dots)
        amps, ratio, share = spectrum(dots)
        rows.append({"n": len(dots), "iou": iou(dots, source_poly), "min_adj": md,
                     "ok": not errs, "errs": errs, "ratio": ratio, "share": share,
                     "dials": [[round(a_, 2), k] for a_, k in amps[:4]], "dots": dots})

    print(f"\n{'n':>3}{'IoU':>7}{'min_gap':>9}{'c4:c5':>7}{'dials in 4':>12}  ok")
    for r in rows:
        flag = "ok" if r["ok"] else "FAIL " + "; ".join(r["errs"])
        dials = " ".join(f"{a_:.1f}@{k:+d}" for a_, k in r["dials"][:2])
        print(f"{r['n']:>3}{r['iou']:>7.3f}{r['min_adj']:>9.2f}{r['ratio']:>7.2f}"
              f"{r['share']:>11.0%}  {flag}   {dials}")

    ok = [r for r in rows if r["ok"]]
    if not ok:
        sys.exit("every dot budget failed validation - reject this asset")
    best = max(ok, key=lambda r: r["iou"])
    knee = next((r for r in ok if r["iou"] >= best["iou"] - 0.01), best)
    chosen = next((r for r in rows if r["n"] == a.dots), None) if a.dots else knee
    if chosen is None:
        sys.exit(f"no valid row at n={a.dots}; valid: {[r['n'] for r in ok]}")
    if not chosen["ok"]:
        sys.exit(f"n={chosen['n']} fails validation: {chosen['errs']}")

    stem = pathlib.Path(a.out or ".") / name
    stem.parent.mkdir(parents=True, exist_ok=True)
    json.dump(chosen["dots"], open(f"{stem}-dots.json", "w"), indent=1)
    preview(name, outer, chosen["dots"], chosen, f"{stem}-preview.png")

    print(f"\nknee n={knee['n']} IoU={knee['iou']:.3f}; best n={best['n']} IoU={best['iou']:.3f}")
    print(f"chosen n={chosen['n']} IoU={chosen['iou']:.3f} min_gap={chosen['min_adj']:.2f} "
          f"c4:c5={chosen['ratio']:.2f}")
    if chosen["ratio"] < 1.3:
        print("WARN c4:c5 below 1.3: which harmonic is dial 4 is near-arbitrary; "
              "small dot edits reshuffle the puzzle - prefer another asset.")
    print(f"wrote {stem}-dots.json  and  {stem}-preview.png")
    print("NEXT: look at the PNG. If it reads, post the draft (validates first, then reads the schedule back):")
    print(f"  python3 {SKILL_DIR}/scripts/svg_pipeline.py post {stem}-dots.json --name {name}")


def _key():
    for line in pathlib.Path("/opt/data/.env").read_text().splitlines():
        if line.startswith("FOURIER_AGENT_KEY="):
            return line.split("=", 1)[1].strip()
    sys.exit("FOURIER_AGENT_KEY missing from /opt/data/.env")


def cmd_post(a):
    """Validate dots.json with validate_puzzle.py, POST as draft, read the row back."""
    import subprocess

    dots = json.load(open(a.dots_json))
    spec = " ".join(f"{x},{y}" for x, y in dots)
    cmd = [sys.executable, str(SKILL_DIR / "scripts" / "validate_puzzle.py"),
           "--dots", spec, "--name", a.name]
    if not a.dry_run:
        cmd.append("--post")
    done = subprocess.run(cmd, capture_output=True, text=True)
    out = done.stdout.strip().splitlines()
    print("\n".join(out[-6:]))  # verdict lines; the ASCII picture is not an assessment
    if done.returncode:
        sys.exit(done.returncode)
    if a.dry_run:
        print("(dry run: nothing posted)")
        return

    # A 201 is not proof -- read the schedule back.
    resp = [l for l in out if "POST RESPONSE" in l]
    print(resp[0] if resp else "")
    try:
        pid = int("".join(ch for ch in (resp[0].split('"id":')[1].split(",")[0]) if ch.isdigit())) if resp else None
    except Exception:
        pid = None
    key = _key()
    req = urllib.request.Request(
        "http://toy_admin:8080/api/agent/schedule", headers={"Authorization": f"Bearer {key}"})
    try:
        sched = json.load(urllib.request.urlopen(req, timeout=10))
    except Exception as e:
        sys.exit(f"posted, but schedule read-back failed: {e}")
    rows = next((v for v in sched.values() if isinstance(v, list)), []) if isinstance(sched, dict) else sched
    row = next((r for r in rows if pid is not None and r.get("id") == pid), None)
    if row is None:
        row = next((r for r in rows if r.get("name") == a.name), None)
    if row is None:
        sys.exit(f"posted id={pid} but it is not in the schedule -- investigate")
    print(f"READ BACK: id={row.get('id')} name={row.get('name')!r} "
          f"status={row.get('status')!r} showDate={row.get('showDate')!r} "
          f"creator={row.get('creator')!r}")
    if row.get("status") != "draft":
        sys.exit("unexpected status -- not a draft, investigate before anything else")
    print("ok: draft in place, unscheduled. Publishing is a separate human action.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fetch", help="download candidate icons from MDI")
    f.add_argument("names", nargs="+")
    f.add_argument("--dir", default="svg")
    f.set_defaults(func=cmd_fetch)

    s = sub.add_parser("sheet", help="contact sheet + subpath/area report")
    s.add_argument("--dir", default="svg")
    s.set_defaults(func=cmd_sheet)

    b = sub.add_parser("build", help="dots + preview for one icon")
    b.add_argument("source", help="icon name (looked up in --dir) or path to .svg")
    b.add_argument("--dir", default="svg")
    b.add_argument("--dots", type=int, default=None, help="pin the dot count (default: IoU plateau knee)")
    b.add_argument("--max-dots", type=int, default=50)
    b.add_argument("--margin", type=float, default=4.0)
    b.add_argument("--out", default=".")
    b.set_defaults(func=cmd_build)

    p = sub.add_parser("post", help="validate + POST draft + read schedule back")
    p.add_argument("dots_json")
    p.add_argument("--name", required=True)
    p.add_argument("--dry-run", action="store_true", help="validate only, post nothing")
    p.set_defaults(func=cmd_post)

    a = ap.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
