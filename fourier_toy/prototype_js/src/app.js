// Prototype round entry: the home lists four links; each link (#p1…#p4)
// brings up its own dial puzzle against the same star. Hash-routed so the
// deployed single file behaves like the multi-page spec.
import { boot } from './puzzle.js';
import * as P from '../proto.js';

const PUZZLES = {
  p1: {
    title: 'P1 · k dials only',
    dials: 'kkkk',
    desc: 'turn the four frequency slots — the coarsest lever',
    patches: [
      { k: 3 },
      { k: -5 },
      { k: 8 },
      { k: -12 },
    ],
  },
  p2: {
    title: 'P2 · phase dials only',
    dials: 'pppp',
    desc: 'rotate each term\'s contribution',
    patches: [
      { phaseDeg: 0 },
      { phaseDeg: 330 },
      { phaseDeg: 225 },
      { phaseDeg: 180 },
    ],
  },
  p3: {
    title: 'P3 · radius dials only',
    dials: 'rrrr',
    desc: 'size each term\'s contribution',
    patches: [
      { rPct: 72 },
      { rPct: 8 },
      { rPct: 0 },
      { rPct: 0 },
    ],
  },
  p4: {
    title: 'P4 · one dial each, 4th term fixed',
    dials: 'kprx',
    desc: 'term 1 k · term 2 phase · term 3 radius · term 4 fixed',
    patches: [{ k: 3 }, { phaseDeg: 210 }, { rPct: 51 }, {}],
  },
  p5: {
    title: 'P5 · one dial each, k on term 2',
    dials: 'rkpx',
    desc: 'term 1 radius · term 2 k · term 3 phase · term 4 fixed',
    patches: [{ rPct: 72 }, { k: -5 }, { phaseDeg: 225 }, {}],
  },
  p6: {
    title: 'P6 · one dial each, k on term 3',
    dials: 'prkx',
    desc: 'term 1 phase · term 2 radius · term 3 k · term 4 fixed',
    patches: [{ phaseDeg: 0 }, { rPct: 8 }, { k: 8 }, {}],
  },
  p7: {
    title: 'P7 · flower · one dial each, k on term 3',
    shape: 'flower',
    dials: 'prkx',
    desc: 'the P6 arrangement on a 6-petal flower — petal modes k±5/±7',
    patches: [{ phaseDeg: 90 }, { rPct: 72 }, { k: 5 }, {}],
  },
  p8: {
    title: 'P8 · fish · one dial each, k on term 3',
    shape: 'fish',
    dials: 'prkx',
    desc: 'the P6 arrangement on a fish drawn from its terms',
    patches: [{ phaseDeg: 345 }, { rPct: 72 }, { k: -4 }, {}],
  },
  p9: {
    title: 'P9 · quaver · one dial each, k on term 3',
    shape: 'quaver',
    dials: 'prkx',
    desc: 'the P6 arrangement on a quaver — an eighth note with its flag',
    patches: [{ phaseDeg: 355 }, { rPct: 73 }, { k: -5 }, {}],
  },
  p10: {
    title: 'P10 · flower · all four dialed',
    shape: 'flower',
    dials: 'prkr',
    desc: 'two radius dials: a fat one on term 2 (38%), a micro trim on term 4 (5%)',
    patches: [{ phaseDeg: 90 }, { rPct: 72 }, { k: 5 }, { rPct: 16 }],
  },
};

const root = document.getElementById('app');

function home() {
  const cards = Object.entries(PUZZLES)
    .map(
      ([id, pz]) =>
        `<a class="card" href="#${id}"><b>${pz.title}</b><span>${pz.desc}</span></a>`,
    )
    .join('');
  root.innerHTML = `
    <p class="intro">Dial experiments against four targets: the sketch's star,
    a 6-petal flower, a fish drawn from its terms, and a quaver (♪). The
    puzzle terms are each shape's <em>real</em> fourier coefficients (the
    k=0 centroid is fixed and never shown as a dial). Match the dashed target
    by closing the solid red line.</p>
    ${cards}
    <p class="note">match = RMS pointwise distance to the target trace, normalized
    by the target's RMS polar radius · solved at ≥ 95% · the star's board tops
    out at ≈ 97.7% (the traced star is not exactly a 4-term curve); the flower
    is an exact 4-term shape (tops at 100%); the fish's target carries 25
    fixed higher-harmonic extras (baked into both traces) so it reads like
    the drawn fish, and its four dials still solve it exactly · steppers: k
    ±1, phase ±5°, radius ±2% of the shape's biggest dialable radius · a
    wrong k on a shape's dominant term shows 0 — no partial credit; the same
    wrong k on a small term is graded gently · generated from
    fourier_sketch's pipeline, no hand-copied numbers.</p>`;
}

function route() {
  const pz = PUZZLES[location.hash.slice(1)];
  if (pz) boot(root, pz);
  else home();
}

window.addEventListener('hashchange', route);
route();