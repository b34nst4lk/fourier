// fourier_toy's canvases: the board (dashed target + epicycle circles +
// comet) and three dial columns (each term's epicycle in miniature, one
// controlled indicator per dial kind). Modelled on fourier_sketch_ffi.mjs's
// panel-2 loop with its guardrails: 30fps draw cap, DPR ≤ 2, dirty gate,
// batched paths, terms dedupe, rebuild-cache only on terms change.
//
// What the columns add to the board contract:
//   - ONE clock for all four canvases: same `t`, same SPEED, one RAF pump. A
//     column and the board circle it mirrors can never disagree.
//   - Kind codes drive BEHAVIOR (which symbology a column draws); the slot
//     ORDINAL drives COLOUR. `ffi.gleam` maps DialP→0, DialR→1, DialK→2 as a
//     local wire detail; the board's chain circles use the same ordinal ink,
//     so a column and its circle always agree. For the standard arrangement
//     (phase, radius, k) ordinal ≡ kind visually; the roles stay distinct.
//   - The radius column's unit is the shape-static `dial_max_r` (pushed with
//     the shape): recomputing it from the live dial rows would move the unit
//     with the dial. Scale = r / (2·dial_max_r) of the space, so the 200%
//     ceiling fills the space exactly and nothing can overflow.
//   - Column canvases (`col-0..2`) bind exactly like the board: payloads stash
//     unconditionally, a boot binds late, a missing canvas is skipped (never
//     an error).
//
// Differences from the sibling:
//   - 50% of the sibling's max speed (SPEED 0.125 laps/s vs 0.25).
//   - Always-on comet (no pause/final frames — the toy's liveliness IS the
//     illustration).
//   - Two traces: a dashed TARGET (static per shape) and the player's comet.
//   - No selection highlight; no IntersectionObserver (single above-fold
//     canvas in a narrow column).
//   - The comet draws the FULL metric synthesis: the three dialable terms
//     chained first, the extras chained after them as real (mostly sub-pixel)
//     epicycles — comet, pen and score all share one formula
//     (shapes.position_at), so the illustration matches what the score
//     measures at every dial position.
//   - Theme: the toy owns the toggle, so the caller pushes dark/light
//     directly (no MutationObserver).

const SPEED = 0.125; // laps per second — 50% of the sibling's max (0.25)
const STEPS = 512; // trace resolution — matches the metric's sampling
const MAX_DPR = 2;
const FRAME_MS = 1000 / 30;
const CHUNKS = 12; // comet alpha chunks
const TAIL_FRAC = 1.0; // fraction of the lap drawn by the comet — a full lap,
// so the tail begins exactly where the head is: no seam at the lap's start
const COMET_TAIL = 0.4; // comet alpha floor — the whole lap stays readable
const COMET_TIP = 0.85; // comet alpha at the pen
const COMET_WIDTH = 2.6; // the comet's ordinary stroke width

// Two DRAW-STATE effects that ride the same clock as the comet. Neither
// touches the payload, the wire or the score — they only decide how the next
// frames paint.
const PULSE_MS = 600; // press-highlight window
const PULSE_WIDTH = 3; // the emphasis ring's width (board circles 1, rings 1.5)
const PULSE_ALPHA = 0.9; // the emphasis's alpha at the press
const PULSE_SWELL = 0.15; // the emphasis ring's radius factor − 1
const REVEAL_MS = 2000; // solve-reveal window
const REVEAL_WIDTH = 1.5; // × the comet's ordinary width
const TRAIL_SEGS = 6; // the k column's trail segments
const TRAIL_SWEEP = Math.PI / 4; // 45° behind the arm tip
const TRAIL_MIN_ALPHA = 0.15; // the farthest segment's alpha
const TRAIL_WIDTH = 2; // the trail's stroke width

// Kind codes — ffi.gleam's LOCAL mapping of puzzle.DialKind. They are
// BEHAVIOR: phase draws the start marker, radius scales the ring, k is the
// fixed ring whose arm speed is the feedback. Colour never reads these.
const KIND_PHASE = 0;
const KIND_RADIUS = 1;
const KIND_K = 2;

const BOARD_ID = "toy-board";
const COLUMN_IDS = ["col-0", "col-1", "col-2"];

// One bound canvas: `el` is the live element, `ctx` its 2D context (null when
// the platform has none — jsdom, a privacy-restricted browser). w/h/dpr are
// the last fitted CSS size and backing-store scale.
function make_view(id) {
  return { id: id, el: null, ctx: null, w: 0, h: 0, dpr: 0 };
}

const views = {
  board: make_view(BOARD_ID),
  cols: COLUMN_IDS.map(make_view),
};

function all_views() {
  return [views.board, ...views.cols];
}

function any_ctx() {
  if (views.board.ctx) return true;
  for (const view of views.cols) if (view.ctx) return true;
  return false;
}

const anim = {
  started: false,
  shape: null, // {centroid:[cx,cy], target:[[x,y]...], extras:[[k,r,deg]...], dialMaxR}
  chain: [], // draw-order rows [k, r, deg, ordinal, movable] (rebuilt in rebuild)
  dial: [], // [[k, radius, deg], ...] the three dialable terms
  kinds: [], // per-dial KIND codes (behavior), parallel to `dial`
  trace: null, // Float64Array(2*STEPS): full-lap cache of the metric synthesis
  dialKey: null,
  shapeKey: null,
  t: 0,
  last: null,
  lastDraw: -Infinity,
  raf: null,
  dirty: true,
  dark: false,
  // press-highlight + solve reveal: draw-state only.
  // A request is PENDING until the next frame stamps it with that frame's own
  // timestamp — so both windows are measured on the draw clock, never on a
  // wall-clock read taken mid-draw.
  pulsePending: -1, // the slot canvas_pulse() pushed, not yet stamped
  pulseSlot: -1, // the stamped slot (its circle + its column ring emphasise)
  pulseAt: -Infinity,
  revealPending: false,
  revealAt: -Infinity,
};

// The ink scheme: black ink on white (light) / white ink on black (dark), with
// exactly three term colours — ORDINAL ink: the 1st
// dialed column/term is red, the 2nd yellow, the 3rd blue, always. Colour
// answers "which wheel in the chain?"; the dial KIND answers "what does this
// wheel do?" through symbology (marker / ring size / arm speed). Extras stay a
// neutral scaffold wash.
//
// Light-mode yellow is #8a6d00, NOT a bright print-yellow: #c9a411 measures
// 2.39:1 on the white card and 2.31:1 on the page paper — below the 3:1
// non-text floor and far below the 4.5:1 a text-coloured ink needs (the page
// wears the same hex). #8a6d00 measures 4.92:1 on the card / 4.75:1 on the
// paper: legibility wins, and the hue is still the radius ink.
const PALETTES = {
  light: {
    ink: [
      "#c8321e", // ordinal 0 — 5.34:1 on the white card
      "#8a6d00", // ordinal 1 — 4.92:1 on the card (darkened print-yellow)
      "#1f5fae", // ordinal 2 — 6.35:1 on the white card
    ],
    neutral: "rgba(17,17,17,0.18)", // non-dialable rows: scaffold, not ink
    target: "rgba(17,17,17,0.35)", // the dashed target: barely there
    trace: "#111", // comet
    pen: "#111", // pen dot
  },
  dark: {
    ink: [
      "#e05a4a", // ordinal 0 — 5.37:1 on #0b0b0b
      "#ffd93d", // ordinal 1 — 14.29:1 on #0b0b0b
      "#5aa0e8", // ordinal 2 — 7.15:1 on #0b0b0b
    ],
    neutral: "rgba(245,245,245,0.10)",
    target: "rgba(245,245,245,0.25)",
    trace: "#f5f5f5",
    pen: "#f5f5f5",
  },
};

// ordinal → palette entry; an ordinal beyond the palette (positions 4–6 are
// reserved) falls back to scaffold ink rather than inventing a colour
function ordinal_ink(index, pal) {
  return index >= 0 && index < pal.ink.length ? pal.ink[index] : pal.neutral;
}

function palette() {
  return palette_for(anim.dark);
}

function palette_for(dark) {
  return dark ? PALETTES.dark : PALETTES.light;
}

function fit(view, dpr) {
  const rect = view.el.getBoundingClientRect();
  const w = Math.max(1, Math.floor(rect.width));
  const h = Math.max(1, Math.floor(rect.height));
  if (view.w !== w || view.h !== h || view.dpr !== dpr) {
    view.w = w;
    view.h = h;
    view.dpr = dpr;
    view.el.width = Math.floor(w * dpr);
    view.el.height = Math.floor(h * dpr);
    anim.dirty = true;
  }
}

function pump() {
  if (anim.raf === null && any_ctx()) {
    anim.raf = requestAnimationFrame(frame);
  }
}

function frame(now) {
  anim.raf = null;
  if (!any_ctx()) return;
  // a pulse/reveal pushed between frames starts at the frame that paints it
  if (anim.pulsePending >= 0) {
    anim.pulseSlot = anim.pulsePending;
    anim.pulseAt = now;
    anim.pulsePending = -1;
    anim.dirty = true;
  }
  if (anim.revealPending) {
    anim.revealAt = now;
    anim.revealPending = false;
    anim.dirty = true;
  }
  const dt = anim.last === null ? 0 : Math.min((now - anim.last) / 1000, 0.05);
  anim.last = now;
  if (now - anim.lastDraw >= FRAME_MS) {
    anim.t = (anim.t + dt * SPEED) % 1;
    anim.lastDraw = now;
    anim.dirty = true;
  }
  if (anim.dirty) {
    anim.dirty = false;
    const dpr = Math.min(Math.max(window.devicePixelRatio || 1, 1), MAX_DPR);
    // fit only on frames that paint: 4 layout reads per DRAWN frame, not per
    // display frame (the 30fps gate runs below the browser's 60fps tick)
    for (const view of all_views()) if (view.ctx) fit(view, dpr);
    draw_all(now);
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

// the arrangement is part of the payload: a re-arranged puzzle re-inks the
// board and re-behaves the columns even when the terms happen to be unchanged
function kinds_equal(a, b) {
  if (a === b) return true;
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

let boot_retry = null;

// Bind every canvas that exists — the board and the three dial columns — and
// boot LATE when Lustre hasn't mounted them yet.
// Why late boots happen: the Lustre runtime runs init effects before its
// first render (runtime/client/runtime.ffi.mjs: #handleEffects precedes
// #render), and hashchange syncs run before the RAF-deferred render — so a
// sync can arrive while no canvas is in the DOM. Callers stash their payload
// unconditionally; this only binds + fits + pumps, so a late boot simply
// starts painting the stashed payload (sibling pattern — the proven
// fourier_sketch_ffi flow). A missing canvas (the headless case, or a DOM
// that has not mounted the columns yet) is skipped, never an error; it binds
// the next time a payload arrives after it mounts.
function ensure_boot() {
  const dpr = Math.min(Math.max(window.devicePixelRatio || 1, 1), MAX_DPR);
  let found = 0;
  for (const view of all_views()) {
    const el = document.getElementById(view.id);
    if (!el) continue;
    found++;
    if (view.el === el && view.ctx) continue; // bound to this live element
    // fresh or remounted element: reset the tracked dims so fit() rewrites
    // the backing store even when the CSS size is unchanged (a new canvas
    // ships 300×150; a same-size rebind must not skip el.width/height)
    if (view.el !== el) {
      view.el = el;
      view.w = 0;
      view.h = 0;
      view.dpr = 0;
    }
    try {
      view.ctx = el.getContext("2d");
    } catch (err) {
      // headless test environments without 2D contexts: the app stays
      // upright, the loop stays idle (dials/score/theme run purely in the DOM)
      view.ctx = null;
    }
    if (view.ctx) fit(view, dpr);
    anim.dirty = true;
  }
  if (found === 0) {
    // nothing mounted yet: schedule at most one pending retry per frame
    // (self-terminating: the retry chain stops the moment a canvas is found)
    if (boot_retry === null) {
      boot_retry = requestAnimationFrame(() => {
        boot_retry = null;
        ensure_boot();
      });
    }
    return;
  }
  if (!anim.started) {
    anim.started = true;
    if (document.body) anim.dark = document.body.getAttribute("data-theme") === "dark";
  }
  anim.dirty = true;
  pump();
}

export function canvas_shape(centroid, target, extras, dial_max_r) {
  // The payload stashes UNCONDITIONALLY — a pre-mount sync (see
  // ensure_boot) must survive until the canvas exists. Boot is orthogonal.
  // gleam lists arrive as cons iterables: normalize to arrays.
  // `dial_max_r` is the radius dial's STATIC unit (the biggest dialable radius):
  // the radius column scales by r / (2·dial_max_r), and deriving that unit from
  // the live dial rows would move the ceiling with the dial.
  const centroidArr = [centroid[0], centroid[1]];
  const targetArr = Array.from(target, (p) => [p[0], p[1]]);
  const extrasArr = Array.from(extras, (t) => [t[0], t[1], t[2]]);
  const maxR = Number(dial_max_r);
  const key =
    JSON.stringify(centroidArr) +
    JSON.stringify(targetArr) +
    JSON.stringify(extrasArr) +
    JSON.stringify(maxR);
  if (anim.shapeKey !== key) {
    anim.shapeKey = key;
    anim.shape = {
      centroid: centroidArr,
      target: targetArr,
      extras: extrasArr,
      dialMaxR: maxR,
    };
    rebuild();
  }
  anim.dirty = true;
  ensure_boot();
}

export function canvas_terms(dial, kinds) {
  // dial rows arrive as tuples #(k, r, phase_deg) — index, don't record-access —
  // and the arrangement arrives as its KIND codes (ffi.gleam's local mapping):
  // behavior (marker / ring size / arm speed) reads the KIND, colour reads the
  // slot ORDINAL. Same unconditional-stash rule as canvas_shape: payload
  // first, boot after.
  const flat = Array.from(dial, (t) => [t[0], t[1], t[2]]);
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

export function canvas_theme(dark) {
  if (anim.dark === dark) return;
  anim.dark = dark;
  anim.dirty = true;
  ensure_boot();
}

/// Press-highlight: the slot that just stepped — its
/// term circle and its column ring pulse for ~600ms. A draw-state request, so
/// it costs nothing on the payload path; a repeat that re-pushes the same slot
/// simply re-arms the window.
export function canvas_pulse(slot) {
  const s = Math.trunc(Number(slot));
  if (!Number.isFinite(s) || s < 0) return; // an unknown slot pulses nothing
  anim.pulsePending = s;
  anim.dirty = true;
  pump();
}

/// Solve reveal: the comet goes solid over the target
/// for ~2s at the solve crossing. Fired beside the solve POST, never in front
/// of it — the network side keeps its own timing and retry rules.
export function canvas_reveal() {
  anim.revealPending = true;
  anim.dirty = true;
  pump();
}

// rebuild_cache: one lap of the FULL metric synthesis — the dial terms plus
// the fixed extras, every term rotating at its own k (exactly the score's
// shapes.synth_trace — the extras are NOT a constant offset). Also caches
// the draw-order chain: [k, radius, deg, ordinal, movable] — the three dial
// rows carry their slot ordinal (their ink) and are movable; the extras are
// scaffold (ordinal −1, neutral wash). O(STEPS × terms) — the dedupe pays for
// itself on every no-op sync, exactly like the sibling.
function rebuild() {
  if (!anim.shape) return;
  anim.chain = [];
  for (let i = 0; i < anim.dial.length; i++) {
    const t = anim.dial[i];
    anim.chain.push([t[0], t[1], t[2], i, true]);
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

// ---- drawing ----

// the press-highlight's remaining strength: 1 at the press, 0 when the window
// closes — eased out (a punch that settles, not a linear fade)
function pulse_strength(now) {
  if (!Number.isFinite(anim.pulseAt) || anim.pulseSlot < 0) return 0;
  const p = (now - anim.pulseAt) / PULSE_MS;
  if (p >= 1) return 0;
  const q = 1 - (p <= 0 ? 0 : p);
  return q * q;
}

// the solve reveal's window: full alpha + bolder comet over the dashed target
function reveal_active(now) {
  return Number.isFinite(anim.revealAt) && now - anim.revealAt < REVEAL_MS;
}

function draw_all(now) {
  draw_board(now);
  for (let i = 0; i < views.cols.length; i++) draw_column(i, now);
}

function draw_board(now) {
  const view = views.board;
  const ctx = view.ctx;
  if (!ctx) return;
  const pal = palette();
  // the press-highlight is one window for the whole board: the pressed term
  // circle and its column's ring share the strength
  const pulse = pulse_strength(now);
  const revealed = reveal_active(now);
  // the backing store is w·dpr — without this mapping everything paints into
  // its top-left quarter on retina screens (sibling's first-draw step)
  ctx.setTransform(view.dpr, 0, 0, view.dpr, 0, 0);
  ctx.clearRect(0, 0, view.w, view.h);
  if (!anim.shape || !anim.trace) return;

  // sketch space 0..100 letterboxed into the canvas (same mapping as the
  // sibling's panel: square content centered, never stretched)
  const scale = Math.min(view.w, view.h) / 100;
  const ox = (view.w - scale * 100) / 2;
  const oy = (view.h - scale * 100) / 2;
  const sx = (x) => ox + scale * x;
  const sy = (y) => oy + scale * y;

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
  const chain = anim.chain;
  const n = chain.length;
  const t = anim.t;

  // chain centers for ALL terms at the current t — circles, links and the
  // pen tip all read this one pass, so they cannot drift apart
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

  // circles: one beginPath+stroke PER ROW, in the row's own ink — a dial term
  // wears its ORDINAL colour (the chain position, not the kind), everything
  // else (the rotating extras) is the neutral wash. Per-row strokes cost
  // nothing measurable (≤ 30 rows) and are what makes the colour legible as
  // data. Sub-pixel radii are skipped: most extras vanish, the visible few are
  // honest epicycles.
  ctx.lineWidth = 1;
  for (let i = 0; i < n; i++) {
    const r = chain[i][1] * scale;
    if (r <= 1.2) continue;
    const row = chain[i];
    ctx.strokeStyle = row[4] ? ordinal_ink(row[3], pal) : pal.neutral;
    ctx.beginPath();
    const X = sx(c[2 * i]);
    const Y = sy(c[2 * i + 1]);
    ctx.moveTo(X + r, Y);
    ctx.arc(X, Y, r, 0, 2 * Math.PI);
    ctx.stroke();
    // press-highlight: the dialed slot's circle takes
    // a thicker emphasis ring in its own full ordinal ink, swelling out and
    // fading back as the window runs out. The base circle above is untouched
    // (the chain geometry is the contract) — the emphasis is drawn over it.
    if (pulse > 0 && row[4] && row[3] === anim.pulseSlot) {
      const R = r * (1 + PULSE_SWELL * pulse);
      ctx.globalAlpha = PULSE_ALPHA * pulse;
      ctx.lineWidth = PULSE_WIDTH;
      ctx.beginPath();
      ctx.moveTo(X + R, Y);
      ctx.arc(X, Y, R, 0, 2 * Math.PI);
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.lineWidth = 1;
    }
  }

  // links: one arm per row, same ink rule (sub-pixel arms skipped)
  for (let i = 0; i < n; i++) {
    const row = chain[i];
    if (row[1] * scale <= 1.2) continue;
    ctx.strokeStyle = row[4] ? ordinal_ink(row[3], pal) : pal.neutral;
    ctx.beginPath();
    ctx.moveTo(sx(c[2 * i]), sy(c[2 * i + 1]));
    ctx.lineTo(sx(c[2 * i + 2]), sy(c[2 * i + 3]));
    ctx.stroke();
  }

  // comet: the cached trace redrawn in alpha-stepped chunks behind the pen.
  // Chunk boundaries end EXACTLY at the sample index (sibling math) so the
  // comet's bright tip is the trace point the pen is about to occupy — no
  // gap, no overshoot.
  const TAIL = Math.floor(TAIL_FRAC * STEPS);
  const idx = Math.max(1, Math.floor(t * STEPS));
  // the reveal bolds the comet 1.5× and pins it at full alpha; otherwise the
  // ordinary 40→85% ramp does the motion reading. The comet is the subject
  // now: bolder than the scaffold.
  ctx.lineWidth = revealed ? COMET_WIDTH * REVEAL_WIDTH : COMET_WIDTH;
  ctx.strokeStyle = pal.trace;
  for (let k = 0; k < CHUNKS; k++) {
    // tail at COMET_TAIL, tip at COMET_TIP, linear across the chunks —
    // the whole lap stays readable while the gradient still shows motion
    ctx.globalAlpha = revealed
      ? 1
      : COMET_TAIL + ((COMET_TIP - COMET_TAIL) * k) / (CHUNKS - 1);
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

  // pen: bright dot at the chain tip — the same pass that drew the circles
  // and links, so the pen can never desync from the comet (whose head is
  // the sample idx = floor(t·STEPS), at most one sample behind the tip)
  ctx.strokeStyle = pal.pen;
  ctx.lineWidth = COMET_WIDTH;
  ctx.beginPath();
  ctx.arc(sx(c[2 * n]), sy(c[2 * n + 1]), 2.2, 0, 2 * Math.PI);
  ctx.stroke();
}

// One dial column = the term's epicycle in miniature, on the board's clock:
// the ring, an arm from the centre to the tip at the exact `position_at` angle
// (2π·k·t + φ), and a pen dot at the tip. The controlled indicator carries the
// DIAL KIND:
//   - phase (kind 0): fixed ring at 0.5 × space + a lone static start-marker
//     dot ON the ring at the dialed phase (the pen's t=0 position; no arm — the
//     pen carries the arm, so the two stay distinguishable when they coincide);
//   - radius (kind 1): ring radius = r / (2·dial_max_r) × space — linear, empty
//     at 0% (nothing drawn at all: no ring, no arm, no pen), the phase ring's
//     size at 100%, the full space at the 200% ceiling;
//   - k (kind 2): fixed ring at 0.5 × space, the arm's speed is the feedback
//     (direction by sign, frozen at k = 0 — the term honestly stops).
// Space is the column's circle space measured from the canvas box: the box's
// smaller side is the diameter of a full-space ring, so `space` is its radius
// unit (phase ring radius = 0.5·space ⇒ diameter = half the box; the radius
// ceiling ⇒ diameter = the box). Nothing can overflow.
function draw_column(i, now) {
  const view = views.cols[i];
  const ctx = view.ctx;
  if (!ctx) return;
  ctx.setTransform(view.dpr, 0, 0, view.dpr, 0, 0);
  ctx.clearRect(0, 0, view.w, view.h);
  if (!anim.shape) return;
  const kind = anim.kinds[i];
  const term = anim.dial[i];
  if (kind === undefined || term === undefined) return;

  const pal = palette();
  const ink = ordinal_ink(i, pal);
  const space = Math.min(view.w, view.h) / 2;
  const cx = view.w / 2;
  const cy = view.h / 2;
  const k = term[0];
  const deg = term[2];
  let ring;
  if (kind === KIND_RADIUS) {
    const maxR = anim.shape.dialMaxR;
    if (!(maxR > 0)) return; // no static unit → nothing honest to scale by
    ring = (term[1] / (2 * maxR)) * space;
  } else {
    ring = 0.5 * space;
  }
  if (!(ring > 0)) return; // r = 0 on the radius column: draw nothing

  ctx.strokeStyle = ink;
  ctx.lineWidth = 1.5;
  // the ring — same moveTo+arc spelling as the board's circles, so a ring
  // stroke is distinguishable from a dot in the op trace
  ctx.beginPath();
  ctx.moveTo(cx + ring, cy);
  ctx.arc(cx, cy, ring, 0, 2 * Math.PI);
  ctx.stroke();

  // press-highlight: the pressed column's ring takes
  // the same beat as its term circle — thicker, fading out over PULSE_MS
  const pulse = pulse_strength(now);
  if (pulse > 0 && anim.pulseSlot === i) {
    ctx.globalAlpha = PULSE_ALPHA * pulse;
    ctx.lineWidth = PULSE_WIDTH;
    ctx.beginPath();
    ctx.moveTo(cx + ring, cy);
    ctx.arc(cx, cy, ring, 0, 2 * Math.PI);
    ctx.stroke();
    ctx.globalAlpha = 1;
    ctx.lineWidth = 1.5;
  }

  // phase column: the lone start-marker dot, ON the ring at the dialed phase.
  // Static (it reads φ, never t); no arm, so it can never be mistaken for the
  // pen even when they coincide.
  if (kind === KIND_PHASE) {
    const marker = (deg * Math.PI) / 180;
    ctx.beginPath();
    ctx.arc(
      cx + ring * Math.cos(marker),
      cy + ring * Math.sin(marker),
      2.2,
      0,
      2 * Math.PI,
    );
    ctx.stroke();
  }

  // the arm: the exact position_at convention — angle = 2π·k·t + φ, so the
  // column's angle, speed and phase are the canvas circle's own numbers
  const a = 2 * Math.PI * k * anim.t + (deg * Math.PI) / 180;

  // arm trail: the k column's speed made legible as
  // motion — six arc segments on the ring over the last 45° BEHIND the tip,
  // alpha stepped 0.15 → 1.0 (the comet's chunk ramp in miniature). Only k
  // rotates: phase has its marker, radius its size, so neither draws one, and
  // a frozen arm (k = 0) has no direction to trail behind.
  if (kind === KIND_K && k !== 0) {
    const dir = k > 0 ? 1 : -1;
    ctx.lineWidth = TRAIL_WIDTH;
    for (let j = TRAIL_SEGS - 1; j >= 0; j--) {
      const near = a - (dir * TRAIL_SWEEP * j) / TRAIL_SEGS;
      const far = a - (dir * TRAIL_SWEEP * (j + 1)) / TRAIL_SEGS;
      // the far end at 15%, the segment touching the tip at 100%
      ctx.globalAlpha = 1 - ((1 - TRAIL_MIN_ALPHA) * j) / (TRAIL_SEGS - 1);
      ctx.beginPath();
      ctx.arc(cx, cy, ring, far, near, far > near);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
    ctx.lineWidth = 1.5;
  }

  const tx = cx + ring * Math.cos(a);
  const ty = cy + ring * Math.sin(a);
  ctx.beginPath();
  ctx.moveTo(cx, cy);
  ctx.lineTo(tx, ty);
  ctx.stroke();

  // pen: the dot at the arm's tip, in the column's ordinal ink
  ctx.beginPath();
  ctx.arc(tx, ty, 2.2, 0, 2 * Math.PI);
  ctx.stroke();
}

export function set_dark(dark) {
  if (document.body) {
    document.body.setAttribute("data-theme", dark ? "dark" : "light");
  }
}

// ---- theme persistence (sibling pattern: f-sketch-theme) -------------------
// Stored choice beats system preference; prefers-color-scheme is the
// fallback when nothing is stored. Every access is guarded — private-mode
// Safari throws on localStorage touch.

const THEME_KEY = "f-toy-theme";

export function theme_load() {
  try {
    const stored = window.localStorage.getItem(THEME_KEY);
    if (stored === "dark") return "dark";
    if (stored === "light") return "light";
  } catch (err) {
    // storage unavailable — fall through to the system preference
  }
  try {
    if (
      window.matchMedia &&
      window.matchMedia("(prefers-color-scheme: dark)").matches
    ) {
      return "dark";
    }
  } catch (err) {
    // no matchMedia either — default light
  }
  return "light";
}

export function theme_save(dark) {
  try {
    window.localStorage.setItem(THEME_KEY, dark ? "dark" : "light");
  } catch (err) {
    // best-effort: storage unavailable — the toggle still works this visit
  }
}

// ---- hold-to-repeat driver for the stepper buttons ---------------------------
// A device-level input concern, so it lives beside the canvas driver: Lustre
// owns the stepping (its click handler stays the single path — each repeat
// is a synthesized `btn.click()`, so dial state, score, and the canvas sync
// exactly like a tap). A QUICK TAP still steps once: repeats only begin
// after a 400ms hold, and the natural release-click that follows a repeated
// hold is swallowed (capture phase, before Lustre's delegated listener) so a
// hold never double-steps. Interval accelerates 120ms → 45ms so long
// travels (a full phase lap, radius 0→100%) take ~2–3s of holding.

const HOLD_INITIAL_MS = 400;
const HOLD_FIRST_MS = 120;
const HOLD_ACCEL = 0.88;
const HOLD_FLOOR_MS = 45;

let hold_timer = null;
let hold_btn = null;
let hold_id; // pointerId of the active hold (undefined for plain Events)
let hold_swallow = false; // a repeat fired — swallow exactly one release click

function hold_clear() {
  if (hold_timer !== null) {
    clearTimeout(hold_timer);
    hold_timer = null;
  }
  hold_btn = null;
}

// the first repeat fires after the initial threshold, then the chain
// restarts at HOLD_FIRST_MS and accelerates toward the floor
function hold_begin(btn) {
  if (hold_btn !== btn) return; // superseded or cleared meanwhile
  hold_swallow = false; // our own synthesized click must pass through
  btn.click(); // disabled buttons suppress clicks — clamps stop the effect
  hold_swallow = true; // arm for the natural release click
  hold_tick(btn, HOLD_FIRST_MS);
}

function hold_tick(btn, delay) {
  hold_timer = setTimeout(() => {
    if (hold_btn !== btn) return;
    hold_swallow = false;
    btn.click();
    hold_swallow = true;
    hold_tick(btn, Math.max(HOLD_FLOOR_MS, delay * HOLD_ACCEL));
  }, delay);
}

export function hold_init() {
  document.addEventListener("pointerdown", (ev) => {
    const btn = ev.target && ev.target.closest ? ev.target.closest("button.btn") : null;
    if (!btn || btn.disabled) return;
    hold_swallow = false; // a new press invalidates any pending swallow
    hold_clear(); // one hold at a time — a second finger takes over
    hold_btn = btn;
    hold_id = ev.pointerId;
    hold_timer = setTimeout(() => hold_begin(btn), HOLD_INITIAL_MS);
  });
  const end =
    (disarm) =>
    (ev) => {
      if (hold_btn === null) return;
      if (hold_id !== undefined && ev.pointerId !== undefined && ev.pointerId !== hold_id) {
        return; // a different pointer's event — ignore
      }
      hold_clear();
      // pointerup: the natural release click is still coming — stay armed;
      // pointerout/pointercancel: no click will follow — disarm or the flag
      // would eat the next innocent tap on this stepper
      if (disarm) hold_swallow = false;
    };
  // pointerup/cancel/out all bubble; pointerleave does not — pointerout is
  // the delegatable "finger slid off the button" signal
  document.addEventListener("pointerup", end(false));
  document.addEventListener("pointercancel", end(true));
  document.addEventListener("pointerout", end(true));
  // long-press on a stepper must not be stolen by a context-menu gesture
  document.addEventListener("contextmenu", (ev) => {
    if (ev.target && ev.target.closest && ev.target.closest("button.btn")) {
      ev.preventDefault();
    }
  });
  // the release-click after a repeated hold: swallow it before Lustre sees
  document.addEventListener(
    "click",
    (ev) => {
      if (hold_swallow && ev.target && ev.target.closest && ev.target.closest("button.btn")) {
        hold_swallow = false;
        ev.stopImmediatePropagation();
        ev.preventDefault();
      }
    },
    true,
  );
}

// ---- the daily puzzle: fetch, identity, storage, telemetry ------------------
// The toy is a static single file, so everything a
// daily puzzle needs beyond the bundle is reached from here: the puzzle
// itself over the API, an anonymous identity, the in-progress attempt, and the
// two fire-and-forget POSTs. Every access is guarded — private-mode storage,
// a missing fetch and a dead network are all ordinary conditions for a toy
// that must still play.

const UID_KEY = "j-uid";
// The backend's `is_uuid_v4` accepts the canonical LOWERCASE form only, so this
// pattern is case-sensitive on purpose: an uppercase value would be reused here
// and then rejected BadUuid on every solve POST — regenerating is the only
// working identity (both generators below already emit lowercase).
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

// The API's `tz` is minutes to ADD to UTC — the opposite sign of
// Date#getTimezoneOffset, which is minutes to SUBTRACT. UTC+2 ⇒ 120.
export function tz_offset_minutes() {
  try {
    const offset = new Date().getTimezoneOffset();
    if (Number.isFinite(offset)) return -offset;
  } catch (err) {
    // no Date? treat as UTC
  }
  return 0;
}

export function ls_get(key) {
  try {
    const value = window.localStorage.getItem(key);
    return value === null ? undefined : value;
  } catch (err) {
    return undefined;
  }
}

export function ls_set(key, value) {
  try {
    window.localStorage.setItem(key, value);
    return true;
  } catch (err) {
    return false;
  }
}

export function ls_del(key) {
  try {
    window.localStorage.removeItem(key);
  } catch (err) {
    // best-effort: nothing to do
  }
}

// The site-wide anonymous identity: created once, reused forever,
// so a player's solves across days are recognised as one player. A stored
// value that is not a CANONICAL LOWERCASE v4 uuid (hand-edited, a different
// app's key) is replaced — the backend refuses anything else.
export function uuid_ensure() {
  const stored = ls_get(UID_KEY);
  if (typeof stored === "string" && UUID_V4.test(stored)) return stored;
  const made = fresh_uuid();
  ls_set(UID_KEY, made);
  return made;
}

function fresh_uuid() {
  try {
    if (window.crypto && typeof window.crypto.randomUUID === "function") {
      return window.crypto.randomUUID();
    }
  } catch (err) {
    // fall through to the Math.random spelling
  }
  // Old browsers: the same v4 shape, weaker randomness — an anonymous toy
  // identity, not a secret.
  const hex = (n) => Math.floor(Math.random() * 16 ** n).toString(16).padStart(n, "0");
  return (
    hex(8) + "-" + hex(4) + "-4" + hex(3) + "-" +
    ((8 + Math.floor(Math.random() * 4)).toString(16)) + hex(3) + "-" + hex(12)
  );
}

// GET /api/puzzle/today?tz=… — resolve exactly once with the body text on a
// 2xx, or with nothing on any failure (network, non-2xx, unreadable body).
// The caller turns the body into a puzzle or a fallback; a daily fetch must
// never throw into the boot path.
export function fetch_puzzle(tz, on_ok, on_error) {
  let settled = false;
  const ok = (text) => {
    if (settled) return;
    settled = true;
    on_ok(text);
  };
  const bad = () => {
    if (settled) return;
    settled = true;
    on_error();
  };
  if (typeof window.fetch !== "function") {
    bad();
    return;
  }
  let pending;
  try {
    // no-store: today's puzzle is derived per request and a cached copy
    // would survive a re-publish
    pending = window.fetch("/api/puzzle/today?tz=" + encodeURIComponent(String(tz)), {
      headers: { accept: "application/json" },
      cache: "no-store",
    });
  } catch (err) {
    bad();
    return;
  }
  Promise.resolve(pending)
    .then((res) => {
      if (!res || res.ok === false) {
        bad();
        return;
      }
      return res.text().then(ok, bad);
    })
    .catch(bad);
}

// POST /api/solve or /api/attempts/abandon: fire-and-forget, but the solve's
// arrival is the only thing that retires the pending report, so a 2xx calls
// back. `keepalive` lets a solve survive the tab closing mid-request. No
// retries: the next boot re-sends an unreported solve.
export function post_telemetry(path, body, on_sent) {
  if (typeof window.fetch !== "function") return;
  try {
    Promise.resolve(
      window.fetch(path, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: body,
        keepalive: true,
      }),
    )
      .then(
        (res) => {
          if (res && res.ok !== false) on_sent();
        },
        () => {
          // dropped: nothing to retry here — the stored attempt still says
          // unsolved/unreported, and the next boot tries again
        },
      )
      .catch(() => {});
  } catch (err) {
    // same: silent by design
  }
}
