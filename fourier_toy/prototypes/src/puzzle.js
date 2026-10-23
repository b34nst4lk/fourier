// Dial-experiment engine: renders one puzzle — the dashed target + the solid
// current overlay, four stepper rows, live aggregate match. Pure prototype:
// no persistence, no reveal, no per-dial hints (aggregate only, per ruling).
import * as P from '../proto.js';

const TGT = P.TARGET.split(' ').map((s) => s.split(',').map(Number));
const TARGET_PATH =
  'M' + P.TARGET.replace(/ /g, 'L').replace(/,/g, ' ') + 'Z';
const K_MIN = -16;
const K_MAX = 16;
const R_UNIT = P.MAX_R / 100; // one radius-percent, in sketch units
const R_MAX = 200 * R_UNIT;
const R_EPS = 1e-9;
const SOLVED_AT = 95;

const KIND = { k: 'k', p: 'phase', r: 'radius', x: 'fixed' };

function startState(patches) {
  return P.TERMS.map((t, i) => {
    const s = { ...t };
    for (const [k, v] of Object.entries(patches[i] || {})) {
      if (k === 'rPct') s.r = v * R_UNIT;
      else s[k] = v;
    }
    return s;
  });
}

function synthesize(st) {
  const pts = new Array(P.N);
  for (let i = 0; i < P.N; i++) {
    const t = i / P.N;
    let x = P.CENTROID[0];
    let y = P.CENTROID[1];
    for (let j = 0; j < st.length; j++) {
      const s = st[j];
      const a = 2 * Math.PI * s.k * t + (s.phaseDeg * Math.PI) / 180;
      x += s.r * Math.cos(a);
      y += s.r * Math.sin(a);
    }
    pts[i] = [x, y];
  }
  return pts;
}

function matchPct(st) {
  const cur = synthesize(st);
  let acc = 0;
  for (let i = 0; i < P.N; i++) {
    const dx = cur[i][0] - TGT[i][0];
    const dy = cur[i][1] - TGT[i][1];
    acc += dx * dx + dy * dy;
  }
  return Math.max(0, (1 - Math.sqrt(acc / P.N) / P.RMS_POLAR) * 100);
}

function pathFor(pts) {
  let d = '';
  for (let i = 0; i < pts.length; i++)
    d += (i ? 'L' : 'M') + pts[i][0].toFixed(2) + ' ' + pts[i][1].toFixed(2);
  return d + 'Z';
}

const fmtK = (k) => (k < 0 ? '−' : '+') + Math.abs(k);
const fmtPhase = (d) => Math.round(d) + '°';
const fmtR = (r) => Math.round(r / R_UNIT) + '%';
const fmtVal = (kind, s) =>
  kind === 'k'
    ? 'k ' + fmtK(s.k)
    : kind === 'phase'
      ? fmtPhase(s.phaseDeg)
      : fmtR(s.r);

const subFor = (kind, s) =>
  kind === 'k'
    ? `locked: r ${fmtR(s.r)} · φ ${fmtPhase(s.phaseDeg)}`
    : kind === 'phase'
      ? `locked: k ${fmtK(s.k)} · r ${fmtR(s.r)}`
      : `locked: k ${fmtK(s.k)} · φ ${fmtPhase(s.phaseDeg)}`;

export function boot(root, pz) {
  const init = startState(pz.patches);
  let st = init.map((s) => ({ ...s }));

  root.innerHTML = `
    <div class="bar">
      <a class="back" href="#">← experiments</a>
      <span class="score">Match <b></b><span class="ok">solved ✓</span></span>
    </div>
    <h2 class="pt">${pz.title}</h2>
    <svg class="board" viewBox="-4 -4 108 108" aria-label="target and current shape">
      <path class="t" d="${TARGET_PATH}" vector-effect="non-scaling-stroke"></path>
      <path class="c" vector-effect="non-scaling-stroke"></path>
    </svg>
    <div class="rows"></div>
    <button class="reset" type="button">reset to start</button>`;

  const rowsEl = root.querySelector('.rows');
  const cells = [];
  const dialChars = pz.dials.split('');
  dialChars.forEach((ch, i) => {
    const kind = KIND[ch];
    const row = document.createElement('div');
    row.className = 'row';
    if (kind === 'fixed') {
      row.innerHTML =
        `<div class="id">term ${i + 1}<span class="sub">fixed, correct: k ${fmtK(st[i].k)} · r ${fmtR(st[i].r)} · φ ${fmtPhase(st[i].phaseDeg)}</span></div>` +
        `<div class="val" style="grid-column: span 3">not a dial</div>`;
    } else {
      row.innerHTML =
        `<div class="id">term ${i + 1}<span class="sub">${subFor(kind, st[i])}</span></div>` +
        `<button type="button" data-i="${i}" data-d="-1">−</button>` +
        `<div class="val"></div>` +
        `<button type="button" data-i="${i}" data-d="1">+</button>`;
    }
    rowsEl.appendChild(row);
    cells[i] = row.querySelector('.val');
  });

  const step = (i, d) => {
    const kind = KIND[dialChars[i]];
    const s = st[i];
    if (kind === 'k') s.k = Math.max(K_MIN, Math.min(K_MAX, s.k + d));
    else if (kind === 'phase')
      s.phaseDeg = ((Math.round(s.phaseDeg) + d * 5) % 360 + 360) % 360;
    else s.r = Math.max(0, Math.min(R_MAX, s.r + d * 2 * R_UNIT));
    render();
  };

  root.addEventListener('click', (e) => {
    if (e.target.closest('.reset')) {
      st = init.map((s) => ({ ...s }));
      render();
      return;
    }
    const b = e.target.closest('button[data-i]');
    if (b) step(+b.dataset.i, +b.dataset.d);
  });

  const curPath = root.querySelector('.c');
  const scoreB = root.querySelector('.score b');
  const scoreSpan = root.querySelector('.score');
  const btns = Array.from(root.querySelectorAll('button[data-i]'));

  const atMin = (kind, s) =>
    (kind === 'k' && s.k <= K_MIN) || (kind === 'radius' && s.r <= R_EPS);
  const atMax = (kind, s) =>
    (kind === 'k' && s.k >= K_MAX) || (kind === 'radius' && s.r >= R_MAX - R_EPS);

  function render() {
    dialChars.forEach((ch, i) => {
      cells[i].textContent =
        KIND[ch] === 'fixed' ? 'not a dial' : fmtVal(KIND[ch], st[i]);
    });
    btns.forEach((b) => {
      const i = +b.dataset.i;
      const kind = KIND[dialChars[i]];
      const d = +b.dataset.d;
      b.disabled = d < 0 ? atMin(kind, st[i]) : atMax(kind, st[i]);
    });
    curPath.setAttribute('d', pathFor(synthesize(st)));
    const m = matchPct(st);
    scoreB.textContent = m.toFixed(1) + '%';
    scoreSpan.classList.toggle('solved', m >= SOLVED_AT);
  }

  render();
}