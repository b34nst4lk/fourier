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

// ---- fish: the sibling app's export CSV (30 rows: k=0 + 29 nonzero) for
// the user's updated fish drawing. Defined purely by terms: the k0 row
// (67.05 at 0.70 rad) is the centroid; the TOP-4 rows are the puzzle's
// dialable truth with phases snapped to the 5° dial grid; the remaining 25
// rows are fixed extras baked identically into the target AND the current
// synthesis (no drawing is shared for this one, so the synthesis IS the
// target by definition — fidelity gate not applicable).
const fishC0 = [67.05 * Math.cos(0.70), 67.05 * Math.sin(0.70)];
const fishTable = [
  [-1, 26.07, -1.85], [1, 16.27, 1.61], [-2, 7.51, -0.34], [2, 4.90, -3.13],
  [3, 2.79, -1.45], [-4, 1.84, 2.32], [4, 1.12, 0.28], [5, 0.78, 2.06],
  [-6, 0.77, -1.07], [-5, 0.63, 0.65], [-8, 0.27, 1.94], [6, 0.23, -2.36],
  [-7, 0.22, -2.74], [10, 0.21, 1.26], [9, 0.20, -0.67], [12, 0.17, -1.58],
  [-3, 0.15, -0.46], [11, 0.14, 2.66], [-13, 0.14, 2.69], [-12, 0.14, -1.70],
  [17, 0.12, -2.51], [8, 0.12, -2.08], [-15, 0.11, -0.96], [13, 0.11, -0.17],
  [19, 0.10, 0.86], [-14, 0.09, 1.18], [-11, 0.09, -0.23], [-22, 0.08, 3.07],
  [-20, 0.07, 0.26],
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

// ---- sk9: the sibling app's export CSV for the user's next drawing ----
// (terms-only fixture, like the fish: the synthesis is the target by
// definition). k0 = 58.30 at 0.81 rad = the centroid; the top-4 = the
// puzzle's dialable truth (phases snapped to the 5° dial grid); the other
// 25 rows = fixed extras baked into target AND current.
const sk9C0 = [58.30 * Math.cos(0.81), 58.30 * Math.sin(0.81)];
const sk9Table = [
  [-1, 17.97, -1.69], [1, 11.30, -0.93], [-3, 4.68, -1.78], [3, 2.83, -2.88],
  [2, 2.48, -2.74], [4, 1.40, -1.37], [-5, 1.33, 2.94], [5, 1.03, -1.04],
  [-2, 0.83, 1.00], [-7, 0.61, -0.49], [-6, 0.61, -0.46], [-4, 0.52, 1.14],
  [-8, 0.41, -2.32], [7, 0.38, 2.46], [-9, 0.37, -2.42], [9, 0.33, -1.68],
  [8, 0.31, -1.76], [-13, 0.14, -1.69], [-11, 0.13, 0.11], [16, 0.12, -1.69],
  [12, 0.12, -1.35], [-12, 0.10, -2.12], [-16, 0.09, -2.70], [-20, 0.09, -2.08],
  [20, 0.08, -2.35], [13, 0.06, -2.01], [10, 0.06, -1.73], [14, 0.06, 2.43],
  [17, 0.06, -1.42],
];
{
  let prev = Infinity;
  for (const [, r] of sk9Table) { if (r > prev + 1e-9) throw new Error('sk9 table not amplitude-sorted'); prev = r; }
}
const sk9Dial = sk9Table.slice(0, 4).map(([k, r, ph]) => ({ k, r, phaseDeg: snap5(normDeg(ph)) }));
const sk9Extras = sk9Table.slice(4).map(([k, r, ph]) => ({ k, r, phaseDeg: normDeg(ph) }));
const sk9All = [...sk9Dial, ...sk9Extras];
const sk9Synth = synthOf(sk9C0[0], sk9C0[1], sk9All);
const sk9Rms = rmsOf(sk9Synth, sk9C0[0], sk9C0[1]);
spanOK(sk9Synth, 'sk9');

// ---- gates ----
const mStar = matchRaw(starPts, starCx, starCy, starRms, starTop4);
if (!(mStar > 96.5 && mStar < 98.5)) throw new Error('star truth out of band: ' + mStar.toFixed(2));
const mFlower = matchRaw(flowerSynth, 50, 50, flowerRms, flowerSpec);
if (mFlower < 99.9) throw new Error('flower truth too low: ' + mFlower.toFixed(2));
const mFish = matchRaw(fishSynth, fishC0[0], fishC0[1], fishRms, fishAll);
if (mFish < 99.9) throw new Error('fish truth too low: ' + mFish.toFixed(2));
console.log('fish centroid :', fishC0.map(v => v.toFixed(3)).join(', '));
const mSk9 = matchRaw(sk9Synth, sk9C0[0], sk9C0[1], sk9Rms, sk9All);
if (mSk9 < 99.9) throw new Error('sk9 truth too low: ' + mSk9.toFixed(2));
console.log('sk9 dialable  :', sk9Dial.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('sk9 centroid  :', sk9C0.map(v => v.toFixed(3)).join(', '));

console.log('star terms    :', starTop4.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('flower terms  :', flowerSpec.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('fish dialable :', fishDial.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('truth match   : star', mStar.toFixed(2) + '% · flower', mFlower.toFixed(3) + '% · fish', mFish.toFixed(3) + '% · sk9', mSk9.toFixed(3) + '%');

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
// (slot3's patched k can coincide with an extras term's k — the sums add,
// nothing breaks; the dial-home state has no such coincidence.)
const m8 = Math.max(0, matchRaw(fishSynth, fishC0[0], fishC0[1], fishRms, withPatches(fishDial, fishMax, p8patches).concat(fishExtras)));
if (m8 >= 95) throw new Error('P8 initial solved: ' + m8);
console.log('P7 initial    :', m7v.toFixed(1) + '%  patches =', JSON.stringify(p7patches));
console.log('P8 initial    :', m8.toFixed(1) + '%  patches =', JSON.stringify(p8patches));
// P9 = P6/P7/P8 arrangement (phase, radius, k, fixed) on sk9; radius start
// 73% (odd parity = can reach the 63%-truth home exactly)
const p9patches = [
  { phaseDeg: (sk9Dial[0].phaseDeg + 90) % 360 },
  { rPct: 73 },
  { k: sk9Dial[2].k - 2 },
  {},
];
const m9 = Math.max(0, matchRaw(sk9Synth, sk9C0[0], sk9C0[1], sk9Rms, withPatches(sk9Dial, sk9Dial[0].r, p9patches).concat(sk9Extras)));
if (m9 >= 95) throw new Error('P9 initial solved: ' + m9);
console.log('P9 initial    :', m9.toFixed(1) + '%  patches =', JSON.stringify(p9patches));

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
// fish: the sibling app's export CSV (30 rows) for the user's updated fish
// drawing (k0 = the centroid; top-4 = dialable truth, phases snapped to the
// dial grid; rows 5..30 = fixed extras baked into target AND current, so
// the dials solve it exactly).
// Span-gated -2..102 (inside the viewBox -4..104 with stroke margin).
export const SHAPES = ${JSON.stringify({
  star: emit(starTop4, starPts, starCx, starCy, starRms, starMax),
  flower: emit(flowerSpec, flowerSynth, 50, 50, flowerRms, flowerMax),
  fish: { ...emit(fishDial, fishSynth, fishC0[0], fishC0[1], fishRms, fishMax), extras: fishExtras },
  sk9: { ...emit(sk9Dial, sk9Synth, sk9C0[0], sk9C0[1], sk9Rms, sk9Dial[0].r), extras: sk9Extras },
})};
`;
writeFileSync('prototypes/proto.js', js);
console.log('proto.js written by generator ✓ (' + js.length + ' bytes)');