// Prototype round entry: the home lists four links; each link (#p1…#p4)
// brings up its own dial puzzle against the same star. Hash-routed so the
// deployed single file behaves like the multi-page spec.
import { boot } from './puzzle.js';
import * as P from '../proto.js';

const PUZZLES = {
  p1: {
    title: 'P1 · k dials only',
    dials: 'kkkk',
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
    patches: [{ k: 3 }, { phaseDeg: 210 }, { rPct: 51 }, {}],
  },
};

const root = document.getElementById('app');

function home() {
  root.innerHTML = `
    <p class="intro">Four dial experiments against the sketch's star. The puzzle
    terms are the star's <em>real</em> top-4 fourier coefficients
    (k = +1, −4, +6, −14; the k=0 centroid is fixed and never shown as a dial).
    Match the dashed target by closing the solid red line.</p>
    <a class="card" href="#p1"><b>P1 · k dials only</b><span>turn the four frequency slots — the coarsest lever</span></a>
    <a class="card" href="#p2"><b>P2 · phase dials only</b><span>rotate each term's contribution</span></a>
    <a class="card" href="#p3"><b>P3 · radius dials only</b><span>size each term's contribution</span></a>
    <a class="card" href="#p4"><b>P4 · one dial each</b><span>term 1 turns k, term 2 turns phase, term 3 turns radius; term 4 is fixed</span></a>
    <p class="note">match = RMS pointwise distance to the traced star, normalized
    like the plan says (target's RMS polar radius) · solved at ≥ 95% · a fully
    solved board tops out at ≈ 97.7% (the 4-term reconstruction never fully
    equals the traced star) · steppers: k ±1, phase ±5°, radius ±2% ·
    generated from fourier_sketch's star preset, no hand-copied numbers.</p>`;
}

function route() {
  const pz = PUZZLES[location.hash.slice(1)];
  if (pz) boot(root, pz);
  else home();
}

window.addEventListener('hashchange', route);
route();