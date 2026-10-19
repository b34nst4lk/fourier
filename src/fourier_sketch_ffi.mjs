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

const SPEED = 0.25; // laps per second
const STEPS = 256;

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
};

export function canvas_boot(id) {
  const el = document.getElementById(id);
  if (!el) return;
  const dpr = Math.max(window.devicePixelRatio || 1, 1);
  const rect = el.getBoundingClientRect();
  const w = Math.max(1, Math.floor(rect.width));
  const h = Math.max(1, Math.floor(rect.height));
  const refit =
    anim.canvas !== el || anim.w !== w || anim.h !== h || anim.dpr !== dpr;
  anim.canvas = el;
  anim.ctx = el.getContext("2d");
  if (refit) {
    anim.w = w;
    anim.h = h;
    anim.dpr = dpr;
    el.width = Math.floor(w * dpr);
    el.height = Math.floor(h * dpr);
  }
  if (!anim.started) {
    anim.started = true;
    window.addEventListener("resize", () => {
      canvas_boot(id);
    });
    requestAnimationFrame(frame);
  }
}

export function canvas_sync(terms, final, playing) {
  anim.terms = terms;
  anim.final = final;
  anim.playing = playing;
  rebuild_cache();
  // final frame should show the complete closed trace immediately
  if (final) anim.t = 1.0;
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
  requestAnimationFrame(frame);
  if (!anim.ctx) return;
  const last = anim.last === null ? now : anim.last;
  const dt = Math.min((now - last) / 1000, 0.05);
  anim.last = now;
  if (!anim.final && anim.playing) anim.t = (anim.t + dt * SPEED) % 1;
  draw();
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

  // epicycle chain: starts at sketch origin, each term rotates its own circle
  let cx = 0;
  let cy = 0;
  ctx.lineWidth = 1;
  for (const term of anim.terms) {
    const r = term[1] * scale;
    if (r > 1.2) {
      ctx.strokeStyle = "rgba(148, 163, 184, 0.28)";
      ctx.beginPath();
      ctx.arc(sx(cx), sy(cy), r, 0, 2 * Math.PI);
      ctx.stroke();
    }
    const ang = 2 * Math.PI * term[0] * t + term[2];
    const nx = cx + term[1] * Math.cos(ang);
    const ny = cy + term[1] * Math.sin(ang);
    ctx.strokeStyle = "rgba(148, 163, 184, 0.55)";
    ctx.beginPath();
    ctx.moveTo(sx(cx), sy(cy));
    ctx.lineTo(sx(nx), sy(ny));
    ctx.stroke();
    cx = nx;
    cy = ny;
  }

  // trace: the portion of this lap drawn so far (full loop in final mode)
  const idx = Math.max(1, Math.floor(t * STEPS));
  ctx.strokeStyle = "#5eead4";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(sx(anim.path[0][0]), sy(anim.path[0][1]));
  for (let i = 1; i <= idx; i++) {
    ctx.lineTo(sx(anim.path[i][0]), sy(anim.path[i][1]));
  }
  ctx.stroke();

  // pen tip
  ctx.fillStyle = "#ffd166";
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
