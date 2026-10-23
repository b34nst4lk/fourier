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

// Gleam-list constructor: the pipeline's functions require real cons lists.
const fromArray = (arr) => list.index_map(list.repeat(undefined, arr.length), (_, i) => arr[i]);

function top4rows(dotsGleam) {
  return Array.from(terms.compute(dotsGleam, N, 5)).filter(t => t.k !== 0).slice(0, 4)
    .map(t => ({ k: t.k, r: Number(t.radius.toFixed(6)), phaseDeg: Number(normDeg(t.phase).toFixed(6)) }));
}
function resamplePts(dotsGleam) {
  return Array.from(resample.resample_closed(dotsGleam, N)).map(p => [p[0], p[1]]);
}
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

// ---- star: sketch.star() 10 dots -> arc-length pipeline. Phases come out
// exactly on-grid (270°), target = the traced star. Board tops ~97.7%.
const starDots = sketch.star();
const starTop4 = top4rows(starDots);
const starPts = resamplePts(starDots);
const [starCx, starCy] = centroidOf(starPts);
const starRms = rmsOf(starPts, starCx, starCy);
spanOK(starPts, 'star');

// ---- flower: parametric 6-petal rose, THETA-uniform parameterization ----
// (arc-length resample smears smooth shapes' spectra — measured: first
// attempt topped at 95.5%). Phases snap to the 5° dial grid; the target is
// REBUILT from the snapped terms: an exact 4-term shape, tops at 100%.
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

// ---- fish: defined BY ITS TERMS (the sibling app's table; the same
// coefficients as the sk=1807,470;7755,6257;7824,655;1553,5911 drawing —
// a two-lobe shape read as a fish). The k0 row (58.00 at 0.61 rad) is the
// centroid; the four nonzero rows are the puzzle truth with phases snapped
// to the 5° dial grid (2.56 rad = 146.65° → 145°, etc.); the target is the
// rebuilt synthesis — exact 4-term shape, tops at 100%.
const fishC0 = [58.00 * Math.cos(0.61), 58.00 * Math.sin(0.61)];
const fishSpec = [
  { k: -1, r: 17.05, phaseDeg: snap5(normDeg(2.56)) },  // 146.65° → 145°
  { k:  1, r: 16.39, phaseDeg: snap5(normDeg(-2.46)) }, // 219.05° → 220°
  { k:  2, r: 11.18, phaseDeg: snap5(normDeg(-1.88)) }, // 252.28° → 250°
  { k: -2, r: 11.00, phaseDeg: snap5(normDeg(-1.20)) }, // 291.25° → 290°
];
const fishSynth = synthOf(fishC0[0], fishC0[1], fishSpec);
const fishRms = rmsOf(fishSynth, fishC0[0], fishC0[1]);
spanOK(fishSynth, 'fish');

// ---- gates ----
const mStar = matchRaw(starPts, starCx, starCy, starRms, starTop4);
if (!(mStar > 96.5 && mStar < 98.5)) throw new Error('star truth out of band: ' + mStar.toFixed(2));
const mFlower = matchRaw(flowerSynth, 50, 50, flowerRms, flowerSpec);
if (mFlower < 99.9) throw new Error('flower truth too low: ' + mFlower.toFixed(2));
const mFish = matchRaw(fishSynth, fishC0[0], fishC0[1], fishRms, fishSpec);
if (mFish < 99.9) throw new Error('fish truth too low: ' + mFish.toFixed(2));
console.log('star terms   :', starTop4.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('flower terms :', flowerSpec.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('fish terms   :', fishSpec.map(t => `k${t.k>0?'+':''}${t.k}·${t.r}·${t.phaseDeg}°`).join('  '));
console.log('truth match  : star', mStar.toFixed(2) + '% · flower', mFlower.toFixed(3) + '% · fish', mFish.toFixed(3) + '%');
console.log('fish centroid :', fishC0.map(v => v.toFixed(3)).join(', '));

// star regression: the four shipped initials must be byte-stable
const starPatches = [
  [{k:3},{k:-5},{k:8},{k:-12}],
  [{phaseDeg:0},{phaseDeg:330},{phaseDeg:225},{phaseDeg:180}],
  [{rPct:72},{rPct:8},{rPct:0},{rPct:0}],
  [{k:3},{phaseDeg:210},{rPct:51},{}],
];
starPatches.forEach((ps, i) => {
  const mv = matchRaw(starPts, starCx, starCy, starRms, withPatches(starTop4, starTop4[0].r, ps));
  if (Math.abs(mv - [-41.4,-39.0,67.1,-44.1][i]) > 0.15)
    throw new Error('star regression P' + (i+1) + ': ' + mv.toFixed(1));
});
console.log('star initials: [-41.4, -39.0, 67.1, -44.1] regressions ok \u2713');

// P8 = P6/P7 arrangement (phase, radius, k, fixed) on the fish.
const starMax = starTop4[0].r, flowerMax = flowerSpec[0].r, fishMax = fishSpec[0].r;
const p7patches = [
  { phaseDeg: (flowerSpec[0].phaseDeg + 90) % 360 },
  { rPct: 72 },
  { k: flowerSpec[2].k - 2 },
  {},
];
const m7 = Math.max(0, matchRaw(flowerSynth, 50, 50, flowerRms, withPatches(flowerSpec, flowerMax, p7patches)));
if (m7 >= 95) throw new Error('P7 initial solved: ' + m7);
const p8patches = [
  { phaseDeg: (fishSpec[0].phaseDeg + 90) % 360 },
  { rPct: 72 },
  { k: fishSpec[2].k - 2 },
  {},
];
const m8 = Math.max(0, matchRaw(fishSynth, fishC0[0], fishC0[1], fishRms, withPatches(fishSpec, fishMax, p8patches)));
if (m8 >= 95) throw new Error('P8 initial solved: ' + m8);
console.log('P7 initial   :', m7.toFixed(1) + '%  patches =', JSON.stringify(p7patches));
console.log('P8 initial   :', m8.toFixed(1) + '%  patches =', JSON.stringify(p8patches));

// ---- emit ----
const emit = (terms, pts, cx, cy, rms, maxR) => ({
  centroid: [Number(cx.toFixed(6)), Number(cy.toFixed(6))],
  rmsPolar: Number(rms.toFixed(6)),
  maxR: Number(maxR.toFixed(6)),
  terms,
  target: pts.map(p => p[0].toFixed(3) + ',' + p[1].toFixed(3)).join(' '),
});
const js = `// GENERATED (scratch script; never hand-edit). Three targets for the dial
// experiments, each self-consistent between target trace and synthesis.
// star: sketch.star()'s 10 dots -> arc-length resample(512) -> DFT -> top-4.
//   Truth phases are the pipeline's (all 270\u00b0, on-grid). Board tops at ~97.7%
//   (the traced star is not exactly a 4-term curve).
// flower: parametric 6-petal rose r = 26*(0.55+0.42*cos(6t+0.6)+0.06*cos(12t)),
//   theta-uniform DFT (no resample: arc-length reparameterization smears the
//   spectrum of smooth shapes \u2014 measured). Truth phases snapped to the 5\u00b0 dial
//   grid and the target REBUILT from the snapped terms: an exact 4-term shape
//   (tops at 100%) and every dial can hit its home.
// fish: defined by its term table from the sibling app (the same
//   coefficients as the user's sk=1807,470;7755,6257;7824,655;1553,5911
//   drawing: two lobes sharing a waist). k0 = centroid (58.00 at 0.61 rad);
//   nonzero phases snapped to the 5\u00b0 dial grid; target = the rebuilt
//   synthesis (exact 4-term shape, tops at 100%).
// k=0 centroid fixed in every synthesis, per shape. Span-gated -2..102
// (inside the viewBox -4..104 with stroke margin).
export const SHAPES = ${JSON.stringify({
  star: emit(starTop4, starPts, starCx, starCy, starRms, starMax),
  flower: emit(flowerSpec, flowerSynth, 50, 50, flowerRms, flowerMax),
  fish: emit(fishSpec, fishSynth, fishC0[0], fishC0[1], fishRms, fishMax),
})};
`;
writeFileSync('prototypes/proto.js', js);
console.log('proto.js written by generator \u2713 (' + js.length + ' bytes)');