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
//     chained first, the fixed extras chained after them as real (mostly
//     sub-pixel) epicycles — comet, pen and score all share one formula
//     (shapes.position_at), so the illustration matches what the score
//     measures at every dial position.
//   - Theme: the toy owns the toggle, so the caller pushes dark/light
//     directly (no MutationObserver).

const SPEED = 0.125; // laps per second — 50% of the sibling's max (0.25)
const STEPS = 512; // trace resolution — matches the metric's sampling
const MAX_DPR = 2;
const FRAME_MS = 1000 / 30;
const CHUNKS = 12; // comet alpha chunks
const TAIL_FRAC = 0.98; // fraction of the lap drawn by the comet
const COMET_TAIL = 0.4; // comet alpha floor — the whole lap stays readable
const COMET_TIP = 0.85; // comet alpha at the pen

const anim = {
  started: false,
  canvas: null,
  ctx: null,
  w: 0,
  h: 0,
  dpr: 1,
  shape: null, // {centroid:[cx,cy], target:[[x,y]...], extras:[[k,r,deg]...]}
  chain: [], // dial rows + extras rows, in draw order (refreshed in rebuild)
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
    circles: "rgba(70, 53, 31, 0.2)",
    links: "rgba(70, 53, 31, 0.45)",
    trace: "#a4372a",
    pen: "#d9a92f",
  },
  dark: {
    target: "rgba(200, 174, 120, 0.55)",
    circles: "rgba(234, 217, 180, 0.095)",
    links: "rgba(234, 217, 180, 0.28)",
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

let boot_retry = null;

// Bind the board canvas, booting LATE when Lustre hasn't mounted it yet.
// Why late boots happen: the Lustre runtime runs init effects before its
// first render (runtime/client/runtime.ffi.mjs: #handleEffects precedes
// #render), and hashchange syncs run before the RAF-deferred render — so a
// sync can arrive while no canvas is in the DOM. Callers stash their
// payload unconditionally; this only binds + fits + pumps, so a late boot
// simply starts painting the stashed payload (sibling pattern — the
// proven fourier_sketch_ffi flow).
function ensure_boot() {
  const el = document.getElementById("toy-board");
  if (!el) {
    // schedule at most one pending retry per frame (self-terminating:
    // the retry chain stops the moment an element is found)
    if (boot_retry === null) {
      boot_retry = requestAnimationFrame(() => {
        boot_retry = null;
        ensure_boot();
      });
    }
    return;
  }
  if (anim.canvas === el && anim.ctx) return; // bound to this live element
  // fresh or remounted element: reset the tracked dims so fit() rewrites
  // the backing store even when the CSS size is unchanged (a new canvas
  // ships 300×150; a same-size rebind must not skip el.width/height)
  if (anim.canvas !== el) {
    anim.canvas = el;
    anim.w = 0;
    anim.h = 0;
    anim.dpr = 0;
  }
  try {
    anim.ctx = el.getContext("2d");
  } catch (err) {
    // headless test environments without 2D contexts: the app stays
    // upright, the loop stays idle (dials/score/theme run purely in the DOM)
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
}

export function canvas_shape(centroid, target, extras) {
  // The payload stashes UNCONDITIONALLY — a pre-mount sync (see
  // ensure_boot) must survive until the canvas exists. Boot is orthogonal.
  // gleam lists arrive as cons iterables: normalize to arrays
  const centroidArr = [centroid[0], centroid[1]];
  const targetArr = Array.from(target, (p) => [p[0], p[1]]);
  const extrasArr = Array.from(extras, (t) => [t[0], t[1], t[2]]);
  const key = JSON.stringify(centroidArr) + JSON.stringify(targetArr) + JSON.stringify(extrasArr);
  if (anim.shapeKey !== key) {
    anim.shapeKey = key;
    anim.shape = { centroid: centroidArr, target: targetArr, extras: extrasArr };
    rebuild();
  }
  anim.dirty = true;
  ensure_boot();
}

export function canvas_terms(dial) {
  // dial rows arrive as tuples #(k, r, phase_deg) — index, don't record-access.
  // Same unconditional-stash rule as canvas_shape: payload first, boot after.
  const flat = Array.from(dial, (t) => [t[0], t[1], t[2]]);
  if (!terms_equal(flat, anim.dial)) {
    anim.dial = flat;
    rebuild();
    anim.dirty = true;
  }
  ensure_boot();
}

export function canvas_theme(dark) {
  if (anim.dark === dark) return;
  anim.dark = dark;
  anim.dirty = true;
  pump();
}

// rebuild_cache: one lap of the FULL metric synthesis — the dial terms plus
// the fixed extras, every term rotating at its own k (exactly the score's
// shapes.synth_trace — the extras are NOT a constant offset). Also caches
// the draw-order chain (dials first, extras after) for the epicycle pass.
// O(STEPS × terms) — the dedupe pays for itself on every no-op sync,
// exactly like the sibling.
function rebuild() {
  if (!anim.shape) return;
  anim.chain = anim.dial.concat(anim.shape.extras);
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

function draw() {
  const ctx = anim.ctx;
  const pal = palette();
  // the backing store is w·dpr — without this mapping everything paints into
  // its top-left quarter on retina screens (sibling's first-draw step)
  ctx.setTransform(anim.dpr, 0, 0, anim.dpr, 0, 0);
  ctx.clearRect(0, 0, anim.w, anim.h);
  if (!anim.shape || !anim.trace) return;

  // sketch space 0..100 letterboxed into the canvas (same mapping as the
  // sibling's panel: square content centered, never stretched)
  const scale = Math.min(anim.w, anim.h) / 100;
  const ox = (anim.w - scale * 100) / 2;
  const oy = (anim.h - scale * 100) / 2;
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

  // circles: one beginPath+stroke over the whole chain (sub-pixel radii
  // skipped — most extras vanish, the visible few are honest epicycles)
  ctx.lineWidth = 1;
  ctx.strokeStyle = pal.circles;
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const r = chain[i][1] * scale;
    if (r <= 1.2) continue;
    const X = sx(c[2 * i]);
    const Y = sy(c[2 * i + 1]);
    ctx.moveTo(X + r, Y);
    ctx.arc(X, Y, r, 0, 2 * Math.PI);
  }
  ctx.stroke();

  // links: one beginPath+stroke (sub-pixel arms skipped)
  ctx.strokeStyle = pal.links;
  ctx.beginPath();
  ctx.moveTo(sx(c[0]), sy(c[1]));
  for (let i = 1; i <= n; i++) {
    if (chain[i - 1][1] * scale > 1.2) {
      ctx.lineTo(sx(c[2 * i]), sy(c[2 * i + 1]));
    }
  }
  ctx.stroke();

  // comet: the cached trace redrawn in alpha-stepped chunks behind the pen.
  // Chunk boundaries end EXACTLY at the sample index (sibling math) so the
  // comet's bright tip is the trace point the pen is about to occupy — no
  // gap, no overshoot.
  const TAIL = Math.floor(TAIL_FRAC * STEPS);
  const idx = Math.max(1, Math.floor(t * STEPS));
  ctx.lineWidth = 1.6;
  ctx.strokeStyle = pal.trace;
  for (let k = 0; k < CHUNKS; k++) {
    // tail at COMET_TAIL, tip at COMET_TIP, linear across the chunks —
    // the whole lap stays readable while the gradient still shows motion
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

  // pen: bright dot at the chain tip — the same pass that drew the circles
  // and links, so the pen can never desync from the comet (whose head is
  // the sample idx = floor(t·STEPS), at most one sample behind the tip)
  ctx.strokeStyle = pal.pen;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.arc(sx(c[2 * n]), sy(c[2 * n + 1]), 2.2, 0, 2 * Math.PI);
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
