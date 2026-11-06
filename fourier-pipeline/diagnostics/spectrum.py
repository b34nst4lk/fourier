"""Report the full dial spectrum for a dots file: top-4 |c_k| (k=0 excluded), c4:c5, share."""
import sys, importlib.util, json

spec = importlib.util.spec_from_file_location(
    "svg_pipeline",
    "/opt/data/profiles/the-cartographer/skills/creative/fourier-puzzle-drafting/scripts/svg_pipeline.py")
sp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sp)

dots = json.load(open(sys.argv[1]))
amps, ratio, share = sp.spectrum(dots)   # amps = [(|c_k|, k)] top-6, k=0 excluded
print("share_in_top4:", round(share * 100, 1), "%")
print("c4:c5:", round(ratio, 2))
for amp, k in amps[:4]:
    print(f"  |c_{k}| = {amp:.1f}")
issues, min_adj = sp.validate(dots)
print("issues:", issues or "none", "min_adj:", round(min_adj, 2))