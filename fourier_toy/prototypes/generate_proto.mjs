// Generates prototypes/proto.js — the fixture data for the dial experiments.
// NEVER hand-edit proto.js; run this script. Imports the sketch's compiled
// pipeline so every number is computed, not copied.
import * as sketch from '/home/jacksim/hermes-users/jacksim/workspace/projects/fourier/fourier_sketch/build/dev/javascript/fourier_sketch/sketch.mjs';
import * as terms from '/home/jacksim/hermes-users/jacksim/workspace/projects/fourier/fourier_sketch/build/dev/javascript/fourier_sketch/terms.mjs';
import * as dft from '/home/jacksim/hermes-users/jacksim/workspace/projects/fourier/fourier_sketch/build/dev/javascript/fourier_sketch/dft.mjs';
import * as complex from '/home/jacksim/hermes-users/jacksim/workspace/projects/fourier/fourier_sketch/build/dev/javascript/fourier_sketch/complex.mjs';
import * as resample from '/home/jacksim/hermes-users/jacksim/workspace/projects/fourier/fourier_sketch/build/dev/javascript/fourier_sketch/resample.mjs';
import * as share from '/home/jacksim/hermes-users/jacksim/workspace/projects/fourier/fourier_sketch/build/dev/javascript/fourier_sketch/sketch_share.mjs';
import * as list from '/home/jacksim/hermes-users/jacksim/workspace/projects/fourier/fourier_sketch/build/dev/javascript/gleam_stdlib/gleam/list.mjs';
import { writeFileSync } from 'node:fs';

const N = 512;
const snap5 = (deg) => ((Math.round(deg / 5) * 5) % 360 + 360) % 360;
const normDeg = (rad) => (((rad * 180 / Math.PI) % 360) + 360) % 360;
const fromArray = (arr) => list.index_map(list.repeat(undefined, arr.length), (_, i) => arr[i]);

function centroidOf(pts) {
  return [pts.reduce((s, p) => s + p[0], 0) / N, pts.reduce((s, p) => s + p[1], 0) / N];
}
function rmsOf(pts, cx, cy) {
  return Math.sqrt(pts.reduce((s, p) => s + ((p[0] - cx) ** 2 + (p[1] - cy) ** 2), 0) / N);
}
function synthOf(cx, cy, st) {
  return Array.from({ length: N }, (_, i) => {
    const t = i / N;
    let x = cx, y = cy;
    for (const s of st) { const a = 2 * Math.PI * s.k * t + s.phaseDeg * Math.PI / 180;
      x += s.r * Math.cos(a); y += s.r * Math.sin(a); }
    return [x, y];
  });
}
function spanOK(pts, name) {
  for (const p of pts) for (const c of p)
    if (!(c > -2 && c < 102) || !isFinite(c)) throw new Error(name + ': coord out of span: ' + p);
}
function matchRaw(pts, cx, cy, rms, st) {
  let acc = 0;
  for (let i = 0; i < N; i++) {
    const t = i / N;
    let x = cx, y = cy;
    for (const s of st) { const a = 2 * Math.PI * s.k * t + s.phaseDeg * Math.PI / 180;
      x += s.r * Math.cos(a); y += s.r * Math.sin(a); }
    const dx = x - pts[i][0], dy = y - pts[i][1];
    acc += dx * dx + dy * dy;
  }
  return (1 - Math.sqrt(acc / N) / rms) * 100;
}
function withPatches(terms, maxR, patches) {
  return terms.map((t, i) => { const o = { ...t };
    for (const [k, v] of Object.entries(patches[i]))
      o[k === 'rPct' ? 'r' : k] = k === 'rPct' ? v / 100 * maxR : v;
    return o; });
}

// ---- star ----
const starTop4 = Array.from(terms.compute(sketch.star(), N, 5)).filter(t => t.k !== 0).slice(0, 4)
  .map(t => ({ k: t.k, r: Number(t.radius.toFixed(6)), phaseDeg: Number(normDeg(t.phase).toFixed(6)) }));
const starPts = Array.from(resample.resample_closed(sketch.star(), N)).map(p => [p[0], p[1]]);
const [starCx, starCy] = centroidOf(starPts);
const starRms = rmsOf(starPts, starCx, starCy);
spanOK(starPts, 'star');

// ---- flower (theta-uniform; phases snapped; target = rebuilt synthesis) ----
const F = 26;
const flowerAt = (t) => {
  const r = F * (0.55 + 0.42 * Math.cos(6 * t + 0.6) + 0.06 * Math.cos(12 * t));
  return [50 + r * Math.cos(t), 50 + r * Math.sin(t)];
};
const flowerSpec = Array.from(dft.forward(fromArray(Array.from({ length: N },
    (_, i) => flowerAt(2 * Math.PI * i / N)))))
  .map(t => ({ k: t[0], amp: complex.magnitude(t[1]), ph: complex.argument(t[1]) }))
  .filter(t => t.k !== 0)
  .sort((a, b) => b.amp - a.amp)
  .slice(0, 4)
  .map(t => ({ k: t.k, r: Number(t.amp.toFixed(6)), phaseDeg: snap5(normDeg(t.ph)) }));
const flowerSynth = synthOf(50, 50, flowerSpec);
const flowerRms = rmsOf(flowerSynth, 50, 50);
spanOK(flowerSynth, 'flower');

// ---- fish: the sibling app's full 30-row term table for the sk= drawing ----
// (k0 = the centroid; the top-4 = the puzzle's dialable truth with phases
// snapped to the 5° dial grid; the remaining 25 rows = fixed extras baked
// identically into the target AND the current synthesis, so the target reads
// like the drawn fish while the four dials still solve it exactly.)
const SK_QUERY = 'v=1&sk=1807,470;7755,6257;7824,655;1553,5911';
const skDots = Array.from(share.from_query(SK_QUERY)[0]);
if (skDots.length !== 4) throw new Error('sk decode: expected 4 dots, got ' + skDots.length);
for (const p of skDots) for (const c of p)
  if (!(c >= 0 && c <= 100)) throw new Error('sk dot out of grid: ' + c);
const skDrawnPts = Array.from(resample.resample_closed(fromArray(skDots), N)).map(p => [p[0], p[1]]);

const fishC0 = [58.00 * Math.cos(0.61), 58.00 * Math.sin(0.61)];
const fishTable = [
  [-1, 17.05, 2.56], [1, 16.39, -2.46], [2, 11.18, -1.88], [-2, 11.00, -1.20],
  [4, 1.72, -0.66], [-4, 1.66, -2.44], [-5, 0.91, -3.04], [6, 0.79, -2.54],
  [-3, 0.77, -1.87], [-6, 0.75, -0.49], [5, 0.74, 3.11], [8, 0.71, -1.34],
  [3, 0.70, 1.67], [-8, 0.66, -1.76], [12, 0.32, -2.01], [-12, 0.29, -1.05],
  [-9, 0.25, -2.42], [9, 0.17, 2.29], [-11, 0.17, 2.78], [-7, 0.15, 2.24],
  [18, 0.14, -1.48], [14, 0.14, -0.82], [-14, 0.13, -2.37], [-18, 0.12, -1.64],
  [7, 0.12, -1.49], [-15, 0.12, -2.90], [16, 0.12, -2.66], [11, 0.11, -2.43],
  [-16, 0.10, -0.30],
];
{
  let prev = Infinity;
  for (const [, r] of fishTable) { if (r > prev + 1e-9) throw new Error('fish table not amplitude-sorted'); prev = r; }
}
const fishDial = fishTable.slice(0, 4).map(([k, r, ph]) => ({ k, r, phaseDeg: snap5(normDeg(ph)) }));
const fishExtras = fishTable.slice(4).map(([k, r, ph]) => ({ k, r, phaseDeg: normDeg(ph) }));
const fishAll = [...fishDial, ...fishExtras];
const fishSynth = synthOf(fishC0[0], fishC0[1], fishAll);
const fishRms = rmsOf(fishSynth, fishC0[0], fishC0[1]);
spanOK(fishSynth, 'fish');

// ---- gates ----
const mStar = matchRaw(starPts, starCx, starCy, starRms, starTop4);
if (!(mStar > 96.5 && mStar < 98.5)) throw new Error('star truth out of band: ' + mStar.toFixed(2));
const mFlower = matchRaw(flowerSynth, 50, 50, flowerRms, flowerSpec);
if (mFlower < 99.9) throw new Error('flower truth too low: ' + mFlower.toFixed(2));
const mFish = matchRaw(fishSynth, fishC0[0], fishC0[1], fishRms, fishAll);
if (mFish < 99.9) throw new Error('fish truth too low: ' + mFish.toFixed(2));
// fidelity: the fish target must now read like the drawn bowtie-fish
const [drawnCx, drawnCy] = centroidOf(skDrawnPts);
const drawnRms = rmsOf(skDrawnPts, drawnCx, drawnCy);
const fishFit = matchRaw(skDrawnPts, fishC0[0], fishC0[1], drawnRms, fishAll);
if (!(fishFit > 95)) throw new Error('fish target too far from drawing: ' + fishFit.toFixed(1) + '%');
const top4Fit = matchRaw(skDrawnPts, fishC0[0], fishC0[1], drawnRms, fishDial);
console.log('fish fidelity : target covers', fishFit.toFixed(1) + '% of the drawn trace (top-4 alone: ' + top4Fit.toFixed(1) + '%)');

console.log('star terms    :', starTop4.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('flower terms  :', flowerSpec.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('fish dialable :', fishDial.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('truth match   : star', mStar.toFixed(2) + '% · flower', mFlower.toFixed(3) + '% · fish', mFish.toFixed(3) + '%');

// star regression: the four shipped initials must stay byte-stable
const starPatches = [
  [{k:3},{k:-5},{k:8},{k:-12}],
  [{phaseDeg:0},{phaseDeg:330},{phaseDeg:225},{phaseDeg:180}],
  [{rPct:72},{rPct:8},{rPct:0},{rPct:0}],
  [{k:3},{phaseDeg:210},{rPct:51},{}],
];
starPatches.forEach((ps, i) => {
  const mv = matchRaw(starPts, starCx, starCy, starRms, withPatches(starTop4, starTop4[0].r, ps));
  if (Math.abs(mv - [-41.4, -39.0, 67.1, -44.1][i]) > 0.15)
    throw new Error('star regression P' + (i + 1) + ': ' + mv.toFixed(1));
});
console.log('star initials : [-41.4, -39.0, 67.1, -44.1] regressions ok ✓');

// P7 / P8 initial gates (phase, radius, k, fixed arrangements)
const starMax = starTop4[0].r, flowerMax = flowerSpec[0].r, fishMax = fishDial[0].r;
const p7patches = [
  { phaseDeg: (flowerSpec[0].phaseDeg + 90) % 360 },
  { rPct: 72 },
  { k: flowerSpec[2].k - 2 },
  {},
];
const m7v = Math.max(0, matchRaw(flowerSynth, 50, 50, flowerRms, withPatches(flowerSpec, flowerMax, p7patches)));
if (m7v >= 95) throw new Error('P7 initial solved: ' + m7v);
const p8patches = [
  { phaseDeg: (fishDial[0].phaseDeg + 90) % 360 },
  { rPct: 72 },
  { k: fishDial[2].k - 2 },
  {},
];
const m8 = Math.max(0, matchRaw(fishSynth, fishC0[0], fishC0[1], fishRms, withPatches(fishDial, fishMax, p8patches).concat(fishExtras)));
if (m8 >= 95) throw new Error('P8 initial solved: ' + m8);
console.log('P7 initial    :', m7v.toFixed(1) + '%  patches =', JSON.stringify(p7patches));
console.log('P8 initial    :', m8.toFixed(1) + '%  patches =', JSON.stringify(p8patches));

// ---- emit ----
const emit = (terms, pts, cx, cy, rms, maxR) => ({
  centroid: [Number(cx.toFixed(6)), Number(cy.toFixed(6))],
  rmsPolar: Number(rms.toFixed(6)),
  maxR: Number(maxR.toFixed(6)),
  terms,
  target: pts.map(p => p[0].toFixed(3) + ',' + p[1].toFixed(3)).join(' '),
});
const js = `// GENERATED (prototypes/generate_proto.mjs; never hand-edit). Three targets
// for the dial experiments, each self-consistent between target trace and
// synthesis. star: sketch.star()'s 10 dots -> arc-length resample(512) -> DFT
// -> top-4 (traced target, board tops ~97.7%). flower: parametric 6-petal
// rose, theta-uniform DFT, phases snapped, target rebuilt (exact, tops 100%).
// fish: the sibling app's full 30-row term table for the sk= drawing (k0 =
// centroid at (47.54, 33.23); top-4 = dialable truth, phases snapped; rows
// 5..30 = fixed extras baked into target AND current, so the target reads
// like the drawn fish — it covers ${fishFit.toFixed(1)}% of the drawn trace, where the
// dialable top-4 alone covers ${top4Fit.toFixed(1)}% — and the dials still solve it exactly).
// Span-gated -2..102 (inside the viewBox -4..104 with stroke margin).
export const SHAPES = ${JSON.stringify({
  star: emit(starTop4, starPts, starCx, starCy, starRms, starMax),
  flower: emit(flowerSpec, flowerSynth, 50, 50, flowerRms, flowerMax),
  fish: { ...emit(fishDial, fishSynth, fishC0[0], fishC0[1], fishRms, fishMax), extras: fishExtras },
})};
`;
writeFileSync('prototypes/proto.js', js);
console.log('proto.js written by generator ✓ (' + js.length + ' bytes)');