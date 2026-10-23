// fourier_toy v2's panel canvas: dashed target + epicycle circles + comet.
// Ported from fourier_sketch_ffi.mjs's panel-2 loop with the guardrails that
// survived its phone-heat audit: 30fps draw cap, DPR ≤ 2, dirty gate,
// batched paths, terms dedupe, rebuild-cache only on terms change.
//
// Differences from the sibling:
//   - 50% of the sibling's max speed (SPEED 0.125 laps/s vs 0.25).
//   - Always-on comet (no pause/final frames — the toy's liveliness IS the
//     illustration; ruled in the prototype-2 grill).
//   - Two traces: a dashed TARGET (static per shape) and the player's comet.
//   - No selection highlight; no IntersectionObserver (single above-fold
//     canvas in a narrow column).
//   - The comet draws the FULL metric synthesis: the four dialable terms
//     chained (circles drawn for them) with the fixed extras summed into the
//     pen position, so the illustration matches what the score measures.
//   - Theme: the toy owns the toggle, so the caller pushes dark/light
//     directly (no MutationObserver).

const SPEED = 0.125; // laps per second — 50% of the sibling's max (0.25)
const STEPS = 512; // trace resolution — matches the metric's sampling
const MAX_DPR = 2;
const FRAME_MS = 1000 / 30;
const CHUNKS = 12; // comet alpha chunks
const TAIL_FRAC = 0.98; // fraction of the lap drawn by the comet

const anim = {
  started: false,
  canvas: null,
  ctx: null,
  w: 0,
  h: 0,
  dpr: 1,
  shape: null, // {centroid:[cx,cy], target:[[x,y]...], extras:[[k,r,deg]...]}
  extrasSum: [0, 0],
  dial: [], // [[k, radius, deg], ...] the four dialable terms
  trace: null, // Float64Array(2*STEPS): full-lap cache of the metric synthesis
  dialKey: null,
  shapeKey: null,
  t: 0,
  last: null,
  lastDraw: -Infinity,
  raf: null,
  dirty: true,
  dark: false,
};

const PALETTES = {
  light: {
    target: "rgba(134, 97, 63, 0.55)",
    circles: "rgba(70, 53, 31, 0.25)",
    links: "rgba(70, 53, 31, 0.55)",
    trace: "#a4372a",
    pen: "#d9a92f",
  },
  dark: {
    target: "rgba(200, 174, 120, 0.55)",
    circles: "rgba(234, 217, 180, 0.12)",
    links: "rgba(234, 217, 180, 0.35)",
    trace: "#d05848",
    pen: "#d9a92f",
  },
};

function palette() {
  return palette_for(anim.dark);
}

function palette_for(dark) {
  return dark ? PALETTES.dark : PALETTES.light;
}

function fit(dpr) {
  const rect = anim.canvas.getBoundingClientRect();
  const w = Math.max(1, Math.floor(rect.width));
  const h = Math.max(1, Math.floor(rect.height));
  if (anim.w !== w || anim.h !== h || anim.dpr !== dpr) {
    anim.w = w;
    anim.h = h;
    anim.dpr = dpr;
    anim.canvas.width = Math.floor(w * dpr);
    anim.canvas.height = Math.floor(h * dpr);
    anim.dirty = true;
  }
}

function pump() {
  if (anim.raf === null && anim.ctx) {
    anim.raf = requestAnimationFrame(frame);
  }
}

function frame(now) {
  anim.raf = null;
  if (!anim.ctx) return;
  fit(Math.min(Math.max(window.devicePixelRatio || 1, 1), MAX_DPR));
  const dt = anim.last === null ? 0 : Math.min((now - anim.last) / 1000, 0.05);
  anim.last = now;
  if (now - anim.lastDraw >= FRAME_MS) {
    anim.t = (anim.t + dt * SPEED) % 1;
    anim.lastDraw = now;
    anim.dirty = true;
  }
  if (anim.dirty) {
    anim.dirty = false;
    draw();
  }
  anim.raf = requestAnimationFrame(frame);
}

function terms_equal(a, b) {
  if (a === b) return true;
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i][0] !== b[i][0] || a[i][1] !== b[i][1] || a[i][2] !== b[i][2]) {
      return false;
    }
  }
  return true;
}

function ensure_boot() {
  const el = document.getElementById("toy-board");
  if (!el) return false;
  anim.canvas = el;
  try {
    anim.ctx = el.getContext("2d");
  } catch (err) {
    // headless test environments without 2D contexts: the app stays upright,
    // the loop stays idle (dials/score/theme run purely in the DOM)
    anim.ctx = null;
  }
  if (anim.ctx) {
    fit(Math.min(Math.max(window.devicePixelRatio || 1, 1), MAX_DPR));
    if (!anim.started) {
      anim.started = true;
      if (document.body) anim.dark = document.body.getAttribute("data-theme") === "dark";
    }
    pump();
  }
  return anim.ctx !== null;
}

export function canvas_shape(centroid, target, extras) {
  if (!anim.ctx && !ensure_boot()) return;
  // gleam lists arrive as cons iterables: normalize to arrays
  const centroidArr = [centroid[0], centroid[1]];
  const targetArr = Array.from(target, (p) => [p[0], p[1]]);
  const extrasArr = Array.from(extras, (t) => [t[0], t[1], t[2]]);
  const key = JSON.stringify(centroidArr) + JSON.stringify(targetArr) + JSON.stringify(extrasArr);
  if (anim.shapeKey === key) return;
  anim.shapeKey = key;
  anim.shape = { centroid: centroidArr, target: targetArr, extras: extrasArr };
  anim.extrasSum = [0, 0];
  for (const t of extras) {
    const a = (t[2] * Math.PI) / 180;
    anim.extrasSum[0] += t[1] * Math.cos(a);
    anim.extrasSum[1] += t[1] * Math.sin(a);
  }
  rebuild();
  anim.dirty = true;
  pump();
}

export function canvas_terms(dial) {
  if (!anim.ctx && !ensure_boot()) return;
  // dial rows arrive as tuples #(k, r, phase_deg) — index, don't record-access
  const flat = Array.from(dial, (t) => [t[0], t[1], t[2]]);
  if (terms_equal(flat, anim.dial)) return;
  anim.dial = flat;
  rebuild();
  anim.dirty = true;
  pump();
}

export function canvas_theme(dark) {
  if (anim.dark === dark) return;
  anim.dark = dark;
  anim.dirty = true;
  pump();
}

// rebuild_cache: one lap of the full metric synthesis (dial terms chained
// + the fixed extras summed in). O(STEPS × terms) — the dedupe pays for
// itself on every no-op sync, exactly like the sibling.
function rebuild() {
  if (!anim.shape) return;
  if (!anim.trace || anim.trace.length !== 2 * STEPS) {
    anim.trace = new Float64Array(2 * STEPS);
  }
  const n = anim.dial.length;
  const [cx0, cy0] = anim.shape.centroid;
  for (let s = 0; s < STEPS; s++) {
    const t = s / STEPS;
    let x = cx0;
    let y = cy0;
    for (let i = 0; i < n; i++) {
      const term = anim.dial[i];
      const a = 2 * Math.PI * term[0] * t + (term[2] * Math.PI) / 180;
      x += term[1] * Math.cos(a);
      y += term[1] * Math.sin(a);
    }
    anim.trace[2 * s] = x + anim.extrasSum[0];
    anim.trace[2 * s + 1] = y + anim.extrasSum[1];
  }
}

// ---- drawing ----

function sx(x) {
  return (x / 100) * anim.w;
}

function sy(y) {
  return (y / 100) * anim.h;
}

function draw() {
  const ctx = anim.ctx;
  const pal = palette();
  ctx.clearRect(0, 0, anim.w, anim.h);
  if (!anim.shape || !anim.trace) return;

  // target: dashed ink trace (static per shape)
  const target = anim.shape.target;
  ctx.strokeStyle = pal.target;
  ctx.lineWidth = 1.6;
  ctx.setLineDash([3, 2.6]);
  ctx.beginPath();
  ctx.moveTo(sx(target[0][0]), sy(target[0][1]));
  for (let i = 1; i < target.length; i++) {
    ctx.lineTo(sx(target[i][0]), sy(target[i][1]));
  }
  ctx.closePath();
  ctx.stroke();
  ctx.setLineDash([]);

  if (!anim.dial.length) return;
  const n = anim.dial.length;
  const t = anim.t;

  // chain centers for the dial terms at the current t (circles drawn for them)
  if (!anim.centers || anim.centers.length < 2 * (n + 1)) {
    anim.centers = new Float64Array(2 * (n + 1));
  }
  const c = anim.centers;
  c[0] = anim.shape.centroid[0];
  c[1] = anim.shape.centroid[1];
  for (let i = 0; i < n; i++) {
    const term = anim.dial[i];
    const a = 2 * Math.PI * term[0] * t + (term[2] * Math.PI) / 180;
    c[2 * (i + 1)] = c[2 * i] + term[1] * Math.cos(a);
    c[2 * (i + 1) + 1] = c[2 * i] + term[1] * Math.sin(a);
  }
  const tipX = c[2 * n] + anim.extrasSum[0];
  const tipY = c[2 * n + 1] + anim.extrasSum[1];

  // circles: one beginPath+stroke (sub-pixel radii skipped)
  ctx.lineWidth = 1;
  ctx.strokeStyle = pal.circles;
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const r = (anim.dial[i][1] / 100) * anim.w;
    if (r <= 1.2) continue;
    const X = sx(c[2 * i]);
    const Y = sy(c[2 * i + 1]);
    ctx.moveTo(X + r, Y);
    ctx.arc(X, Y, r, 0, 2 * Math.PI);
  }
  ctx.stroke();

  // links: one beginPath+stroke (sub-pixel legs skipped)
  ctx.strokeStyle = pal.links;
  ctx.beginPath();
  ctx.moveTo(sx(c[0]), sy(c[1]));
  for (let i = 1; i <= n; i++) {
    if ((anim.dial[i - 1][1] / 100) * anim.w > 1.2) {
      ctx.lineTo(sx(c[2 * i]), sy(c[2 * i + 1]));
    }
  }
  ctx.stroke();

  // comet: the cached trace redrawn in alpha-stepped chunks behind the pen
  const span = Math.floor(TAIL_FRAC * STEPS);
  const chunk = Math.ceil(span / CHUNKS);
  const head = Math.floor(t * STEPS);
  ctx.lineWidth = 1.6;
  ctx.strokeStyle = pal.trace;
  for (let k = 0; k < CHUNKS; k++) {
    ctx.globalAlpha = ((k + 1) / CHUNKS) * 0.85;
    ctx.beginPath();
    const start = head - span + k * chunk;
    for (let s = start; s <= start + chunk; s++) {
      const idx = ((s % STEPS) + STEPS) % STEPS;
      const X = sx(anim.trace[2 * idx]);
      const Y = sy(anim.trace[2 * idx + 1]);
      if (s === start) ctx.moveTo(X, Y);
      else ctx.lineTo(X, Y);
    }
    ctx.stroke();
  }
  ctx.globalAlpha = 1;

  // pen: bright dot at the metric's tip (live position, extra trig is cheap)
  let penX = anim.shape.centroid[0];
  let penY = anim.shape.centroid[1];
  for (let i = 0; i < n; i++) {
    const term = anim.dial[i];
    const a = 2 * Math.PI * term[0] * t + (term[2] * Math.PI) / 180;
    penX += term[1] * Math.cos(a);
    penY += term[1] * Math.sin(a);
  }
  ctx.strokeStyle = pal.pen;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.arc(sx(penX + anim.extrasSum[0]), sy(penY + anim.extrasSum[1]), 2.2, 0, 2 * Math.PI);
  ctx.stroke();
}
// ---- routing ----

export function hash_now() {
  return window.location.hash.replace(/^#/, "");
}

export function hash_set(fragment) {
  const current = hash_now();
  if (current === fragment) return;
  window.location.hash = "#" + fragment;
}

export function hash_watch(handler) {
  window.addEventListener("hashchange", () => handler(hash_now()));
}

export function set_dark(dark) {
  if (document.body) {
    document.body.setAttribute("data-theme", dark ? "dark" : "light");
  }
}
