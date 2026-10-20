export function cos(x) {
  return Math.cos(x);
}

export function sin(x) {
  return Math.sin(x);
}

export function atan2(y, x) {
  return Math.atan2(y, x);
}

export function sqrt(x) {
  return Math.sqrt(x);
}

export function store_get(key, otherwise) {
  try {
    const value = window.localStorage.getItem(key);
    return value === null ? otherwise : value;
  } catch {
    return otherwise;
  }
}

export function store_set(key, value) {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // private browsing / quota errors: autosave is best-effort
  }
}

// Convert a pointer event's client coords into sketch-space (0..100).
// The SVG viewBox is 100x100 letterboxed in its element (default
// preserveAspectRatio), so the conversion accounts for letterbox offsets.
// The element is looked up by id — decoders may receive sanitized events,
// so we never trust event.currentTarget.
export function event_point(event, svg_id, otherwise) {
  try {
    const svg = document.getElementById(svg_id);
    const rect = svg.getBoundingClientRect();
    const scale = Math.min(rect.width, rect.height) / 100;
    const ox = (rect.width - scale * 100) / 2;
    const oy = (rect.height - scale * 100) / 2;
    const x = (event.clientX - rect.left - ox) / scale;
    const y = (event.clientY - rect.top - oy) / scale;
    return [x, y];
  } catch {
    return otherwise;
  }
}
// (now_ms below is for the bench module)
export function now_ms() {
  return performance.now();
}

// ---- panel 2: canvas + requestAnimationFrame epicycle animation -----------
// The loop owns its clock; Gleam pushes state (targets/mode) on model change.
// Trace points are cached in SKETCH coords and mapped per frame, so window
// resizes need no cache rebuild — only a canvas refit.
//
// Thermal/resource guardrails (bench-verified: scripts/bench_render.mjs,
// see the phone-heat audit in docs/PROGRESS.md):
//   1. dirty gate — draw only when t advanced or model state changed;
//      paused/final repaint once per sync, then the RAF chain disengages.
//   2. visibility gate — IntersectionObserver fully stops the loop when the
//      canvas is off-screen (stacked mobile layout keeps it scrolled away).
//   3. frame-rate cap — playing mode draws at ~30fps (visually identical at
//      0.25 laps/s); halves the playing burn.
//   4. DPR cap at 2 — 3× phones would repaint >2× pixels for no visible gain.
//   5. batched paths — circles and links each become ONE beginPath+stroke
//      instead of per-term strokes (~100× fewer stroke calls at defaults).
//   6. sync dedupe — rebuild_cache (O(STEPS×terms) trig) runs only when the
//      pushed terms are value-different from the cached ones.

const SPEED = 0.25; // laps per second
const STEPS = 256;
const MAX_DPR = 2;
const FRAME_MS = 1000 / 30; // playing-mode draw cap

const anim = {
  started: false,
  canvas: null,
  ctx: null,
  w: 0,
  h: 0,
  dpr: 1,
  terms: [], // [[k, radius, phase], ...] top-N, amplitude-sorted
  path: [], // cached trace points in sketch coords (0..100)
  final: false,
  playing: true,
  t: 0,
  last: null,
  lastDraw: -Infinity,
  raf: null, // pending RAF handle (null = loop disengaged)
  dirty: true,
  visible: true,
};

let boot_retry = null; // pending self-re-boot while the canvas is unmounted

function pump() {
  // schedule at most one pending frame; re-arming after idle goes through here
  if (anim.raf === null && anim.visible && anim.ctx) {
    anim.raf = requestAnimationFrame(frame);
  }
}

// Value equality over [k, radius, phase] rows: O(terms), while rebuild_cache
// is O(STEPS×terms) trig — the dedupe pays for itself on every no-op sync.
function terms_equal(a, b) {
  if (a === b) return true;
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i][0] !== b[i][0] || a[i][1] !== b[i][1] || a[i][2] !== b[i][2]
    ) {
      return false;
    }
  }
  return true;
}

export function canvas_boot(id) {
  const el = document.getElementById(id);
  if (!el) {
    // Unmount case: below 3 dots the view swaps in a placeholder and the
    // canvas leaves the DOM. Idle the loop (no painting to a detached canvas)
    // and keep one retry per frame so a later REMOUNT is caught on the next
    // sync-free frame — one getElementById per frame, self-terminating.
    anim.canvas = null;
    anim.ctx = null;
    if (boot_retry === null) {
      boot_retry = requestAnimationFrame(() => {
        boot_retry = null;
        canvas_boot(id);
      });
    }
    return;
  }
  const dpr = Math.min(Math.max(window.devicePixelRatio || 1, 1), MAX_DPR);
  const rect = el.getBoundingClientRect();
  const w = Math.max(1, Math.floor(rect.width));
  const h = Math.max(1, Math.floor(rect.height));
  const refit =
    anim.canvas !== el || anim.w !== w || anim.h !== h || anim.dpr !== dpr;
  const element_changed = anim.canvas !== el;
  anim.canvas = el;
  anim.ctx = el.getContext("2d");
  if (refit) {
    anim.w = w;
    anim.h = h;
    anim.dpr = dpr;
    el.width = Math.floor(w * dpr);
    el.height = Math.floor(h * dpr);
    anim.dirty = true; // backing store changed: repaint once
  }
  if (element_changed) {
    // The IO observes the ORIGINAL element only; after an unmount it fired
    // isIntersecting:false and would never observe the replacement. Rebind
    // it to the new element (observe() queues a fresh intersection report)
    // and reset the gate until that report lands.
    anim.visible = true;
    if (anim.io) {
      anim.io.disconnect();
      anim.io.observe(el);
    }
  }
  if (!anim.started) {
    anim.started = true;
    window.addEventListener("resize", () => {
      canvas_boot(id);
      anim.dirty = true;
      pump();
    });
    if (typeof IntersectionObserver !== "undefined") {
      anim.io = new IntersectionObserver((entries) => {
        const was = anim.visible;
        anim.visible = entries.some((e) => e.isIntersecting);
        if (anim.visible && !was) anim.dirty = true; // stale content while away
        pump();
      });
      anim.io.observe(el);
    }
    pump();
  }
}

export function canvas_sync(terms, final, playing) {
  // Lustre hands over a Gleam List of tuples: iterable, but NOT a JS array —
  // no .length, no index access (draw() crashes with a RangeError otherwise,
  // every frame). Normalize once at the boundary; everything below sees plain
  // rows [k, radius, phase].
  const rows = Array.from(terms, (t) => [t[0], t[1], t[2]]);
  // assign BEFORE rebuilding: rebuild_cache() reads anim.terms, so the trace
  // cache must be rebuilt from the incoming terms, not the previous ones.
  const terms_changed = !terms_equal(anim.terms, rows);
  anim.terms = rows;
  if (terms_changed) rebuild_cache();
  anim.final = final;
  anim.playing = playing;
  // final frame should show the complete closed trace immediately
  if (final) anim.t = 1.0;
  anim.dirty = true;
  pump();
}

function rebuild_cache() {
  const pts = [];
  for (let step = 0; step <= STEPS; step++) {
    const t = step / STEPS;
    let x = 0;
    let y = 0;
    for (const term of anim.terms) {
      const ang = 2 * Math.PI * term[0] * t + term[2];
      x += term[1] * Math.cos(ang);
      y += term[1] * Math.sin(ang);
    }
    pts.push([x, y]);
  }
  anim.path = pts;
}

function frame(now) {
  anim.raf = null;
  // The RAF chain is kept alive only while there is work: playing advances t
  // each capped frame; anything else waits for a dirty flag from canvas_sync,
  // resize, or visibility changes (all routed through pump()). No ctx means
  // the canvas is unmounted — stay idle until boot rebinds it.
  if (!anim.visible || !anim.ctx) return;
  if ((!anim.playing || anim.final) && !anim.dirty) return;
  anim.raf = requestAnimationFrame(frame);

  if (anim.playing && !anim.final) {
    // frame-rate cap: skip trig+draw between capped frames. dt is measured
    // from the last DRAWN frame (anim.last only advances on draws), so pen
    // speed on screen is unchanged by the gating.
    const first = anim.last === null;
    const dt = first ? 0 : Math.min((now - anim.last) / 1000, 0.05);
    if (first || now - anim.lastDraw >= FRAME_MS) {
      if (!first) anim.t = (anim.t + dt * SPEED) % 1;
      anim.lastDraw = now;
      anim.last = now;
      anim.dirty = true;
      draw();
      anim.dirty = false;
    }
  } else if (anim.dirty) {
    draw();
    anim.dirty = false;
    anim.last = now;
  }
}

function draw() {
  const ctx = anim.ctx;
  const w = anim.w;
  const h = anim.h;
  ctx.setTransform(anim.dpr, 0, 0, anim.dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);

  // sketch space 0..100 letterboxed into the canvas (same mapping as the
  // SVG panel's pointer conversion)
  const scale = Math.min(w, h) / 100;
  const ox = (w - scale * 100) / 2;
  const oy = (h - scale * 100) / 2;
  const sx = (x) => ox + scale * x;
  const sy = (y) => oy + scale * y;

  const t = anim.final ? 1.0 : anim.t;

  // chain centers: one pass, shared by circles, links and the pen tip
  const n = anim.terms.length;
  const centers = anim.centers || (anim.centers = []);
  centers.length = n + 1;
  centers[0] = [0, 0];
  let cx = 0;
  let cy = 0;
  for (let i = 0; i < n; i++) {
    const term = anim.terms[i];
    const ang = 2 * Math.PI * term[0] * t + term[2];
    cx += term[1] * Math.cos(ang);
    cy += term[1] * Math.sin(ang);
    centers[i + 1] = [cx, cy];
  }

  ctx.lineWidth = 1;

  // all circles share one stroke style: ONE beginPath+stroke for the whole
  // chain (moveTo avoids connecting chords between arcs) — warm ink wash
  ctx.strokeStyle = "rgba(70, 53, 31, 0.25)";
  ctx.beginPath();
  for (let i = 0; i < n; i++) {
    const r = anim.terms[i][1] * scale;
    if (r > 1.2) {
      const c = centers[i];
      const X = sx(c[0]);
      const Y = sy(c[1]);
      ctx.moveTo(X + r, Y);
      ctx.arc(X, Y, r, 0, 2 * Math.PI);
    }
  }
  ctx.stroke();

  // all links share one stroke style: ONE beginPath+stroke
  ctx.strokeStyle = "rgba(70, 53, 31, 0.55)";
  ctx.beginPath();
  ctx.moveTo(sx(centers[0][0]), sy(centers[0][1]));
  for (let i = 1; i <= n; i++) {
    const c = centers[i];
    ctx.lineTo(sx(c[0]), sy(c[1]));
  }
  ctx.stroke();

  // trace: routes are drawn in red-brick ink on a cartographer's map
  const idx = Math.max(1, Math.floor(t * STEPS));
  ctx.strokeStyle = "#a4372a";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(sx(anim.path[0][0]), sy(anim.path[0][1]));
  for (let i = 1; i <= idx; i++) {
    ctx.lineTo(sx(anim.path[i][0]), sy(anim.path[i][1]));
  }
  ctx.stroke();

  // pen tip (chain end = last center) — a gold coin marker
  ctx.fillStyle = "#d9a92f";
  ctx.beginPath();
  ctx.arc(sx(cx), sy(cy), 3, 0, 2 * Math.PI);
  ctx.fill();
}

// Slider inputs: read event.target.value as a number (sentinel on failure).
export function event_value(event, otherwise) {
  try {
    const v = Number(event.target.value);
    return Number.isFinite(v) ? v : otherwise;
  } catch {
    return otherwise;
  }
}

// ---- keyboard shortcuts (undo/redo) ----------------------------------------
// Wired once; the Gleam side hands over a dispatch closure taking a Bool
// (true = redo) so JS never has to construct Gleam records.
let keys_wired = false;

export function wire_keys(send) {
  if (keys_wired) return;
  keys_wired = true;
  window.addEventListener("keydown", (e) => {
    if (!(e.ctrlKey || e.metaKey)) return;
    const k = (e.key || "").toLowerCase();
    if (k === "z") {
      e.preventDefault();
      send(!e.shiftKey);
    } else if (k === "y") {
      e.preventDefault();
      send(true);
    }
  });
}
