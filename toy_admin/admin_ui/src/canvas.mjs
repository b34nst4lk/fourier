// admin_ui's canvas drivers — two panels, one file.
//
// PORTED from fourier_toy_ffi.mjs (itself from fourier_sketch_ffi.mjs). The
// test-play board MUST feel like the toy, so this keeps the toy's loop verbatim:
// SPEED 0.125 laps/s, STEPS 512 (the metric's sampling), DPR ≤ 2, a 30fps draw
// cap, the dirty gate, the batched epicycle pass (one beginPath per class), the
// extras-chained comet, and the pen that reads the SAME chain-centre pass as the
// circles so it cannot drift. Deviations, all deliberate:
//   - the canvas id is a parameter of the boot (one board per view);
//   - the loop STOPS when its canvas leaves the DOM (the editor swaps views,
//     the toy never did) — otherwise a stale element keeps the CPU awake;
//   - `event_point` maps a pointer into the drawing panel's 0..100 space
//     (fourier_sketch's letterbox math, square panel);
//   - `draw_render` paints the authoring panel: the polygon through the dots
//     plus the draft's closing edge — no target, no comet, no animation
//     (nothing is derived in the browser: the fixture comes from the API);
//   - the test-play board wears the TOY'S ink scheme (index.html /
//     fourier_toy_ffi.mjs PALETTES): one colour per dial KIND — red phase,
//     yellow radius, blue k, neutral wash for non-dialable terms — keyed on
//     dial.kind_code, never on the slot index (the arrangement is data).
//
// Sketch space is 0..100 with y growing DOWN (the toys' convention); every
// panel is square and letterboxed, never stretched.

const SPEED = 0.125; // laps per second — the toy's own pace
const STEPS = 512; // trace resolution — matches the metric's sampling
const MAX_DPR = 2;
const FRAME_MS = 1000 / 30;
const CHUNKS = 12; // comet alpha chunks
const TAIL_FRAC = 0.98; // fraction of the lap drawn by the comet
const COMET_TAIL = 0.4; // comet alpha floor — the whole lap stays readable
const COMET_TIP = 0.85; // comet alpha at the pen

const PLAY_ID = "play-board";
const DRAW_ID = "draw-canvas";

// The toy's ink scheme, verbatim (fourier_toy_ffi.mjs PALETTES) — the test-play
// board must look like the thing it previews. Keyed on dial.Kind::kind_code:
// the colour follows the KIND, so a re-arranged fixture keeps red phase /
// yellow radius / blue k / neutral fixed. Light-mode yellow is the print-yellow
// darkened until it clears the contrast floor on white (4.92:1; #c9a411 is
// 2.39:1 — unreadable); the admin PAGE stays parchment, only the canvas ink
// follows the scheme.
const PALETTES = {
  light: {
    phase: "#c8321e",
    radius: "#8a6d00",
    k: "#1f5fae",
    neutral: "rgba(17,17,17,0.18)",
    target: "rgba(17,17,17,0.35)",
    trace: "#111",
    pen: "#111",
  },
  dark: {
    phase: "#e05a4a",
    radius: "#ffd93d",
    k: "#5aa0e8",
    neutral: "rgba(245,245,245,0.10)",
    target: "rgba(245,245,245,0.25)",
    trace: "#f5f5f5",
    pen: "#f5f5f5",
  },
};

const KIND_FIXED = 3; // dial.kind_code(KindFixed)

// kind code -> palette entry; anything unknown is scaffold ink
function term_color(kind, pal) {
  switch (kind) {
    case 0:
      return pal.phase;
    case 1:
      return pal.radius;
    case 2:
      return pal.k;
    default:
      return pal.neutral;
  }
}

function dark_mode() {
  return document.body?.getAttribute("data-theme") === "dark";
}

function palette() {
  return dark_mode() ? PALETTES.dark : PALETTES.light;
}

// ---------- pointer -> sketch space ----------

// Map a pointer event on `draw-canvas` into 0..100 sketch coordinates. The
// panel is square and letterboxed: pick the smaller side, offset the rest.
// (fourier_sketch_ffi's event_point, with getElementById as the fallback —
// Lustre's delegated listener can leave currentTarget empty.)
//
// Returns a 3-tuple `[x, y, inside]`: Gleam tuples are plain JS arrays, so the
// FFI never has to build a Prelude value. `inside` false (a letterbox sliver,
// or a headless test with no layout) means "not a dot".
export function event_point(event) {
  const el =
    event?.currentTarget ??
    event?.target ??
    document.getElementById(DRAW_ID);
  if (!el || typeof el.getBoundingClientRect !== "function") return [0, 0, false];
  const rect = el.getBoundingClientRect();
  if (!rect.width || !rect.height) return [0, 0, false];
  const scale = Math.min(rect.width, rect.height) / 100;
  const ox = (rect.width - scale * 100) / 2;
  const oy = (rect.height - scale * 100) / 2;
  const x = (event.clientX - rect.left - ox) / scale;
  const y = (event.clientY - rect.top - oy) / scale;
  // a tap outside the square (letterbox sliver) is not a dot
  if (x < 0 || x > 100 || y < 0 || y > 100) return [0, 0, false];
  return [x, y, true];
}

// ---------- authoring panel ----------

const draw_state = { canvas: null, ctx: null, w: 0, h: 0, dpr: 0, path: "", dots: [] };

// The paint is payload-first/boot-second, like the play loop's ensure_boot: the
// payload (path + dots) is stashed immediately, and one frame-paced retry —
// never a queue, never a busy loop — paints it as soon as the canvas exists.
// Why: a view swap (BackToAuthoring / StartNew / StartEdit) fires the paint
// effect in the same turn the DOM is patched, so getElementById can still miss
// the canvas it is about to mount; the old code dropped that paint silently and
// nothing retriggered it (the drawing appeared only after the next dot tap).
// Bounded so a paint aimed at a view that never mounts (a stale effect) ends.
const DRAW_RETRY_FRAMES = 60; // ~1s at 60fps: plenty for a view swap
const draw_retry = { pending: false, tries: 0 };

function draw_next_frame(fn) {
  if (typeof requestAnimationFrame === "function") {
    requestAnimationFrame(fn);
  } else {
    setTimeout(fn, 16);
  }
}

function draw_fit() {
  const el = draw_state.canvas;
  const rect = el.getBoundingClientRect();
  const w = Math.max(1, Math.floor(rect.width));
  const h = Math.max(1, Math.floor(rect.height));
  const dpr = Math.min(Math.max(window.devicePixelRatio || 1, 1), MAX_DPR);
  if (draw_state.w === w && draw_state.h === h && draw_state.dpr === dpr) return;
  draw_state.w = w;
  draw_state.h = h;
  draw_state.dpr = dpr;
  el.width = Math.floor(w * dpr);
  el.height = Math.floor(h * dpr);
}

// Paint the stashed payload onto whatever canvas is in the DOM right now.
// Returns false when there is nothing to paint onto YET (no canvas, no 2d
// context) — the caller decides whether to try again.
function draw_paint() {
  const el = document.getElementById(DRAW_ID);
  if (!el) return false;
  if (el !== draw_state.canvas) {
    // A new element (the view swapped): its backing store is empty, so the fit
    // cache belongs to the old canvas and must not be trusted.
    draw_state.canvas = el;
    draw_state.ctx = null;
    draw_state.w = 0;
    draw_state.h = 0;
    draw_state.dpr = 0;
  }
  try {
    draw_state.ctx = el.getContext("2d");
  } catch (err) {
    draw_state.ctx = null;
  }
  const ctx = draw_state.ctx;
  if (!ctx) return false;
  draw_fit();

  const pal = palette();
  const scale = Math.min(draw_state.w, draw_state.h) / 100;
  const ox = (draw_state.w - scale * 100) / 2;
  const oy = (draw_state.h - scale * 100) / 2;
  // one transform for the whole panel: everything below is in sketch units
  ctx.setTransform(
    draw_state.dpr * scale,
    0,
    0,
    draw_state.dpr * scale,
    draw_state.dpr * ox,
    draw_state.dpr * oy,
  );
  ctx.clearRect(
    -ox / scale,
    -oy / scale,
    draw_state.w / scale,
    draw_state.h / scale,
  );

  // the shape's outline, in sketch units (the polygon the derivation resamples)
  // — faint target ink, a neutral wash inside it, solid ink for the dots
  ctx.lineWidth = 0.9;
  ctx.strokeStyle = pal.target;
  ctx.fillStyle = pal.neutral;
  if (draw_state.path) {
    ctx.fill(new Path2D(draw_state.path));
    ctx.stroke(new Path2D(draw_state.path));
  }

  // the dots themselves
  ctx.fillStyle = pal.trace;
  for (const [x, y] of draw_state.dots) {
    ctx.beginPath();
    ctx.arc(x, y, 1.1, 0, 2 * Math.PI);
    ctx.fill();
  }
  return true;
}

// Payload first, boot second: the effect can land before Lustre has mounted the
// canvas (a view swap patches the DOM around the effect), so a failed paint
// keeps the payload and retries once per frame until the canvas exists.
export function draw_render(path, dots) {
  draw_state.path = path;
  draw_state.dots = Array.from(dots, (p) => [p[0], p[1]]);
  draw_retry.tries = 0; // a fresh payload gets a fresh budget
  if (draw_paint()) return;
  draw_retry_more();
}

// ONE pending attempt at a time; each attempt is a frame, the payload is read
// fresh each time (a newer draw_render supersedes this one), and the budget
// bounds the chain so a paint for a view that never mounts ends quietly.
function draw_retry_more() {
  if (draw_retry.pending) return;
  if (draw_retry.tries >= DRAW_RETRY_FRAMES) return;
  draw_retry.tries += 1;
  draw_retry.pending = true;
  draw_next_frame(() => {
    draw_retry.pending = false;
    if (!draw_paint()) draw_retry_more();
  });
}

// ---------- test-play board (the toy's loop) ----------

const anim = {
  started: false,
  stopped: false,
  canvas: null,
  ctx: null,
  w: 0,
  h: 0,
  dpr: 1,
  shape: null, // {centroid, target, extras}
  chain: [], // draw-order rows [k, r, deg, slot, movable] (rebuilt in rebuild)
  dial: [], // [[k, radius, deg], ...]
  kinds: [], // per-dial colour codes (dial.kind_code), parallel to `dial`
  trace: null,
  dialKey: null,
  shapeKey: null,
  t: 0,
  last: null,
  lastDraw: -Infinity,
  raf: null,
  dirty: true,
};

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
  if (anim.raf === null && anim.ctx && !anim.stopped) {
    anim.raf = requestAnimationFrame(frame);
  }
}

function frame(now) {
  anim.raf = null;
  // the editor swaps views: a canvas that left the DOM must stop the loop
  if (!anim.ctx || (anim.canvas && !anim.canvas.isConnected)) {
    anim.ctx = null;
    anim.canvas = null;
    return;
  }
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

let boot_retry = null;

function ensure_boot() {
  const el = document.getElementById(PLAY_ID);
  if (!el) {
    if (boot_retry === null) {
      boot_retry = requestAnimationFrame(() => {
        boot_retry = null;
        ensure_boot();
      });
    }
    return;
  }
  if (anim.canvas === el && anim.ctx) return;
  if (anim.canvas !== el) {
    anim.canvas = el;
    anim.w = 0;
    anim.h = 0;
    anim.dpr = 0;
    anim.stopped = false;
  }
  try {
    anim.ctx = el.getContext("2d");
  } catch (err) {
    anim.ctx = null;
  }
  if (anim.ctx) {
    fit(Math.min(Math.max(window.devicePixelRatio || 1, 1), MAX_DPR));
    anim.started = true;
    pump();
  }
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

function triple(term) {
  return [term[0], term[1], term[2]];
}

// the arrangement is part of the payload: a re-arranged fixture re-inks the
// board even when the terms happen to be unchanged
function kinds_equal(a, b) {
  if (a === b) return true;
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

// `centroid` and `target` arrive as plain arrays already (the view converts);
// `extras` and `dial` are `#(k, r, phase_deg)` tuples — index, never record
// access, at the FFI boundary.
export function play_shape(centroid, target, extras) {
  const centroidArr = [centroid[0], centroid[1]];
  const targetArr = Array.from(target, (p) => [p[0], p[1]]);
  const extrasArr = Array.from(extras, triple);
  const key = JSON.stringify(centroidArr) + JSON.stringify(targetArr) + JSON.stringify(extrasArr);
  if (anim.shapeKey !== key) {
    anim.shapeKey = key;
    anim.shape = { centroid: centroidArr, target: targetArr, extras: extrasArr };
    rebuild();
  }
  anim.dirty = true;
  ensure_boot();
}

export function play_terms(dial, kinds) {
  const flat = Array.from(dial, triple);
  const kindArr =
    kinds === undefined || kinds === null ? [] : Array.from(kinds, (k) => k | 0);
  if (!terms_equal(flat, anim.dial) || !kinds_equal(kindArr, anim.kinds)) {
    anim.dial = flat;
    anim.kinds = kindArr;
    rebuild();
    anim.dirty = true;
  }
  ensure_boot();
}

// Stop the loop when the test-play view is left (a no-op when it is idle).
export function play_stop() {
  anim.stopped = true;
  if (anim.raf !== null) {
    cancelAnimationFrame(anim.raf);
    anim.raf = null;
  }
  anim.ctx = null;
  anim.canvas = null;
  anim.started = false;
  // the next mount is a fresh element: forget the cached payload keys so it
  // repaints from scratch even if the dials did not move
  anim.shapeKey = null;
  anim.dialKey = null;
}

// One lap of the FULL metric synthesis: dial terms first, extras chained after,
// each rotating at its own k — the score's `synth_trace` exactly.
function rebuild() {
  if (!anim.shape) return;
  // [k, radius, deg, slot, movable]: dial rows carry their slot and wear their
  // kind's ink when the arrangement leaves them movable; the extras are
  // scaffold (slot −1, neutral wash)
  anim.chain = [];
  for (let i = 0; i < anim.dial.length; i++) {
    const t = anim.dial[i];
    const kind = anim.kinds[i];
    anim.chain.push([t[0], t[1], t[2], i, kind !== undefined && kind !== KIND_FIXED]);
  }
  for (const t of anim.shape.extras) {
    anim.chain.push([t[0], t[1], t[2], -1, false]);
  }
  if (!anim.trace || anim.trace.length !== 2 * STEPS) {
    anim.trace = new Float64Array(2 * STEPS);
  }
  const n = anim.chain.length;
  const [cx0, cy0] = anim.shape.centroid;
  for (let s = 0; s < STEPS; s++) {
    const t = s / STEPS;
    let x = cx0;
    let y = cy0;
    for (let i = 0; i < n; i++) {
      const term = anim.chain[i];
      const a = 2 * Math.PI * term[0] * t + (term[2] * Math.PI) / 180;
      x += term[1] * Math.cos(a);
      y += term[1] * Math.sin(a);
    }
    anim.trace[2 * s] = x;
    anim.trace[2 * s + 1] = y;
  }
}

function draw() {
  const ctx = anim.ctx;
  const pal = palette();
  ctx.setTransform(anim.dpr, 0, 0, anim.dpr, 0, 0);
  ctx.clearRect(0, 0, anim.w, anim.h);
  if (!anim.shape || !anim.trace) return;

  const scale = Math.min(anim.w, anim.h) / 100;
  const ox = (anim.w - scale * 100) / 2;
  const oy = (anim.h - scale * 100) / 2;
  const sx = (x) => ox + scale * x;
  const sy = (y) => oy + scale * y;

  // the target: dashed ink trace, static per shape
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
  const chain = anim.chain;
  const n = chain.length;
  const t = anim.t;

  // chain centres for ALL terms at this t — circles, links and the pen tip read
  // this one pass, so they cannot drift apart
  if (!anim.centers || anim.centers.length < 2 * (n + 1)) {
    anim.centers = new Float64Array(2 * (n + 1));
  }
  const c = anim.centers;
  c[0] = anim.shape.centroid[0];
  c[1] = anim.shape.centroid[1];
  for (let i = 0; i < n; i++) {
    const term = chain[i];
    const a = 2 * Math.PI * term[0] * t + (term[2] * Math.PI) / 180;
    c[2 * (i + 1)] = c[2 * i] + term[1] * Math.cos(a);
    c[2 * (i + 1) + 1] = c[2 * i + 1] + term[1] * Math.sin(a);
  }

  // circles: one beginPath+stroke PER ROW, in the row's own ink — a movable
  // dial term wears its kind's colour, the fixed slot and the rotating extras
  // the neutral wash (sub-pixel radii skipped)
  ctx.lineWidth = 1;
  for (let i = 0; i < n; i++) {
    const r = chain[i][1] * scale;
    if (r <= 1.2) continue;
    const row = chain[i];
    ctx.strokeStyle = row[4] ? term_color(anim.kinds[row[3]], pal) : pal.neutral;
    ctx.beginPath();
    const X = sx(c[2 * i]);
    const Y = sy(c[2 * i + 1]);
    ctx.moveTo(X + r, Y);
    ctx.arc(X, Y, r, 0, 2 * Math.PI);
    ctx.stroke();
  }

  // links: one arm per row, same ink rule (sub-pixel arms skipped)
  for (let i = 0; i < n; i++) {
    const row = chain[i];
    if (row[1] * scale <= 1.2) continue;
    ctx.strokeStyle = row[4] ? term_color(anim.kinds[row[3]], pal) : pal.neutral;
    ctx.beginPath();
    ctx.moveTo(sx(c[2 * i]), sy(c[2 * i + 1]));
    ctx.lineTo(sx(c[2 * i + 2]), sy(c[2 * i + 3]));
    ctx.stroke();
  }

  // comet: the cached trace in alpha-stepped chunks behind the pen; chunk
  // boundaries end exactly at the sample index, so the bright tip is the point
  // the pen is about to occupy
  const TAIL = Math.floor(TAIL_FRAC * STEPS);
  const idx = Math.max(1, Math.floor(t * STEPS));
  ctx.lineWidth = 2.6; // the comet is the subject: bolder than the scaffold
  ctx.strokeStyle = pal.trace;
  for (let k = 0; k < CHUNKS; k++) {
    ctx.globalAlpha = COMET_TAIL + ((COMET_TIP - COMET_TAIL) * k) / (CHUNKS - 1);
    const a0 = idx - TAIL + Math.floor((TAIL * k) / CHUNKS);
    const a1 = idx - TAIL + Math.floor((TAIL * (k + 1)) / CHUNKS);
    ctx.beginPath();
    for (let s = a0; s <= a1; s++) {
      const wrap = ((s % STEPS) + STEPS) % STEPS;
      const X = sx(anim.trace[2 * wrap]);
      const Y = sy(anim.trace[2 * wrap + 1]);
      if (s === a0) ctx.moveTo(X, Y);
      else ctx.lineTo(X, Y);
    }
    ctx.stroke();
  }
  ctx.globalAlpha = 1;

  // the pen: bright dot at the chain tip, from the same pass as the circles
  ctx.strokeStyle = pal.pen;
  ctx.lineWidth = 2.6;
  ctx.beginPath();
  ctx.arc(sx(c[2 * n]), sy(c[2 * n + 1]), 2.2, 0, 2 * Math.PI);
  ctx.stroke();
}
