// Boot/payload + dial-column contract for the v2 canvases (pure Node, no DOM
// deps — house bench pattern from fourier_sketch/scripts/bench_render.mjs).
//
// Two contracts live here:
//
// 1. Boot/payload (PLAN-dial-columns §4, retained from the board contract).
//    The premise, verified in Lustre's runtime source (runtime/client/
//    runtime.ffi.mjs, constructor): init effects run BEFORE the first render —
//      this.#handleEffects(effects);   // ← sync_effect fires here
//      this.#render();                 // ← the canvas mounts here
//    and hashchange dispatches run effects synchronously while renders are
//    RAF-deferred — so a canvas sync can arrive before its canvas mounts.
//    Contract: the payload pushed by a pre-mount sync must SURVIVE until the
//    canvas exists; a late boot must paint it. Payloads are stashed
//    unconditionally and boot (canvas binding) is orthogonal — the sibling
//    fourier_sketch_ffi pattern proven in production. Phase 2 generalizes it
//    from ONE canvas to FOUR (board + the three dial columns).
//
// 2. The dial columns (PLAN-dial-columns §2/§4). Each column canvas is its
//    term's epicycle in miniature, on the board's clock: ring + arm from the
//    centre at the exact position_at angle (2π·k·t + φ) + a pen dot at the tip.
//    - phase column: fixed ring at 0.5 × space, plus a lone static start-marker
//      dot ON the ring at the dialed phase (no arm);
//    - radius column: ring radius = r / (2·dial_max_r) × space — linear, and at
//      r = 0 NOTHING is drawn for that column;
//    - k column: fixed ring at 0.5 × space, the arm's speed is the feedback
//      (k = 0 freezes the arm).
//    "Space" is the column's circle-space radius unit: the canvas box's smaller
//    side is a full-space ring's diameter, so a phase ring (0.5 × space) has
//    diameter = half the box and the radius ceiling fills the box exactly.
//
// Geometry expectations are computed from the SAME math the FFI uses
// (angle = 2πkt + φ), tolerance 1.3px (house pin tolerance). The column
// scenarios run on FRESH module instances (a cache-busting import) so the
// clock starts at t = 0 and the contract can mirror it deterministically.
//
// Run: node scripts/boot_contract.mjs

import * as ffi from "../src/fourier_toy_ffi.mjs";
import * as puzzle from "../build/dev/javascript/fourier_toy/fourier_toy/puzzle.mjs";

// ---- constants shared with the FFI (pinned, not imported) -------------------
const SPEED = 0.125; // laps per second
const FRAME_MS = 1000 / 30; // the 30fps draw gate
const COMET_CHUNKS = 12; // fourier_toy_ffi.mjs CHUNKS
const TOL = 1.3; // px — house geometry tolerance
const RECT = 300; // the stub canvas box (CSS px)
const SPACE = RECT / 2; // the radius-space unit: half the box

const IDS = ["toy-board", "col-0", "col-1", "col-2"];
const BOARD = "toy-board";
const COLS = ["col-0", "col-1", "col-2"];

const KIND_PHASE = 0;
const KIND_RADIUS = 1;
const KIND_K = 2;

// ---- stub DOM (bench_render.mjs pattern) ------------------------------------
//
// The registry models what Lustre has mounted right now: a missing id = no
// canvas in the DOM (home view, or a board sync that ran before the render
// committed).
const mounted = new Map();

function make_ctx() {
  const ops = {
    arc: 0,
    moveTo: 0,
    lineTo: 0,
    stroke: 0,
    clearRect: 0,
    nan: 0,
    setTransform_args: null, // last setTransform() call (DPR contract)
    // one frame's strokes, grouped at the frame's clearRect:
    // [{ pts, arcs, style, width, alpha }, ...] in draw order.
    // `arcs` keeps each arc's centre AND radius, so a ring (arc r = R) is
    // distinguishable from a pen/marker dot (arc r = 2.2).
    draws: [],
    stroke_alphas: [], // globalAlpha at each stroke (comet ramp contract)
  };
  let seg = []; // coords accumulated since the last stroke
  let seg_arcs = []; // arc() calls since the last stroke
  let curAlpha = 1; // current globalAlpha (recorded at stroke time)
  let curStyle = ""; // current strokeStyle (recorded at stroke time)
  let curWidth = 1; // current lineWidth (recorded at stroke time)
  const push = (x, y) => {
    seg.push([x, y]);
    if (!Number.isFinite(x) || !Number.isFinite(y)) ops.nan++;
  };
  const count = (name) => {
    ops[name]++;
  };
  return {
    ops,
    setLineDash: () => {},
    __proto__: null,
    get lineWidth() {
      return curWidth;
    },
    set lineWidth(v) {
      curWidth = v;
    },
    get strokeStyle() {
      return curStyle;
    },
    set strokeStyle(v) {
      curStyle = v;
    },
    get globalAlpha() {
      return curAlpha;
    },
    set globalAlpha(v) {
      curAlpha = v;
    },
    setTransform: (a, b, c, d, e, f) => {
      ops.setTransform_args = [a, b, c, d, e, f];
    },
    clearRect: () => {
      ops.clearRect++;
      ops.draws.push([]); // a new frame starts: the previous one is complete
    },
    beginPath: () => {},
    closePath: () => {},
    moveTo: (x, y) => {
      count("moveTo");
      push(x, y);
    },
    lineTo: (x, y) => {
      count("lineTo");
      push(x, y);
    },
    arc: (x, y, r) => {
      count("arc");
      seg_arcs.push({ x, y, r });
      push(x, y);
    },
    stroke: () => {
      ops.stroke++;
      if (ops.draws.length === 0) ops.draws.push([]);
      ops.draws[ops.draws.length - 1].push({
        pts: seg,
        arcs: seg_arcs,
        style: curStyle,
        width: curWidth,
        alpha: curAlpha,
      });
      ops.stroke_alphas.push(curAlpha);
      seg = [];
      seg_arcs = [];
    },
  };
}

let el_seq = 0;
function make_el(headless = false, rect = { width: RECT, height: RECT }) {
  el_seq++;
  const ctx = headless ? null : make_ctx(); // ONE stable ctx per element
  return {
    id: "el" + el_seq,
    width: 0,
    height: 0,
    getBoundingClientRect: () => ({ ...rect, left: 0, top: 0 }),
    getContext: () => ctx,
  };
}

globalThis.document = {
  body: { getAttribute: () => "light" },
  getElementById: (id) => mounted.get(id) ?? null,
};
globalThis.window = { devicePixelRatio: 2, addEventListener: () => {} };

// browser-faithful RAF: queue + manual ticks, monotonic clock
let raf_q = [];
let raf_handle = 0;
globalThis.requestAnimationFrame = (cb) => {
  raf_handle++;
  raf_q.push(cb);
  return raf_handle;
};
globalThis.cancelAnimationFrame = () => {};
let NOW = 1000.0;
function tick(ms = 16) {
  NOW += ms;
  const q = raf_q;
  raf_q = [];
  for (const cb of q) cb(NOW);
}

// ---- the mount registry ------------------------------------------------------
function mount_all(opts = {}) {
  const made = {};
  for (const id of IDS) {
    const el = make_el(opts.headless === true, opts.rect);
    mounted.set(id, el);
    made[id] = el;
  }
  return made;
}
function unmount_all() {
  mounted.clear();
}
function el_of(id) {
  return mounted.get(id);
}
function ctx_of(id) {
  return el_of(id).getContext();
}

// ---- helpers ----------------------------------------------------------------
let passed = 0;
let failed = 0;
function check(name, ok, detail = "") {
  if (ok) {
    passed++;
    console.log("  ok  " + name);
  } else {
    failed++;
    console.log("FAIL  " + name + (detail ? " — " + detail : ""));
  }
}

const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);

// The exact position_at convention the FFI draws with.
function tip_at(cx, cy, r, k, deg, t) {
  const a = 2 * Math.PI * k * t + (deg * Math.PI) / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
}
// A static point on the ring at the dialed phase (the phase start-marker).
function marker_at(cx, cy, r, deg) {
  const a = (deg * Math.PI) / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
}

// gleam lists arrive as cons iterables: normalize at the boundary
const rows_of = (terms) => Array.from(terms, (t) => [t.k, t.r, t.phase_deg]);

// ffi.gleam's private behavior codes (DialP→0, DialR→1, DialK→2): the FFI
// dispatches on these (symbology), never on them for colour.
function kind_code(kind) {
  if (puzzle.DialKind$isDialP(kind)) return KIND_PHASE;
  if (puzzle.DialKind$isDialR(kind)) return KIND_RADIUS;
  if (puzzle.DialKind$isDialK(kind)) return KIND_K;
  return -1;
}
const kinds_of = (setup) => Array.from(setup.dials, kind_code);

const setup_of = () => puzzle.quaver_setup();

// The exact pushes ffi.gleam makes: canvas_shape(shape) then
// canvas_terms(state, dials) — shape data first (centroid, target, extras,
// dial_max_r), then the rows and their behavior codes.
function sync_board(f, setup) {
  const shape = puzzle.shape_of(setup.shape);
  f.canvas_shape(
    shape.centroid,
    shape.target,
    rows_of(shape.extras),
    shape.dial_max_r,
  );
  const state = puzzle.initial(shape, setup.patches);
  f.canvas_terms(rows_of(state), kinds_of(setup));
  return { shape, state };
}

function step_state(shape, setup, state, slot, dir) {
  const kinds = Array.from(setup.dials);
  const rows = Array.from(state);
  rows[slot] = puzzle.step(kinds[slot], rows[slot], dir, shape.dial_max_r);
  return rows;
}

// The board's last frame, split by draw-order ROLE rather than by a fixed
// offset: the dashed target first, one circle stroke per visible row, one arm
// stroke per visible row, 12 comet chunks, the pen last.
function board_frame(id = BOARD) {
  const ops = ctx_of(id).ops;
  const draw = ops.draws[ops.draws.length - 1] ?? [];
  return {
    draw,
    target: draw[0],
    circles: draw.filter((s) => s.arcs.length === 1 && s.pts.length === 2),
    links: draw.filter((s) => s.arcs.length === 0 && s.pts.length === 2),
    comet: draw.slice(draw.length - 1 - COMET_CHUNKS, draw.length - 1),
    pen: draw[draw.length - 1],
  };
}

// A column's last frame: one ring (moveTo + arc), one arm (moveTo + lineTo),
// a pen dot (arc only), and — on the phase column — the start-marker dot
// (also arc only; drawn before the arm, so the pen is the last dot).
function column_frame(id) {
  const ops = ctx_of(id).ops;
  const draw = ops.draws[ops.draws.length - 1] ?? [];
  const ring = draw.find((s) => s.arcs.length === 1 && s.pts.length === 2) ?? null;
  const arm = draw.find((s) => s.arcs.length === 0 && s.pts.length === 2) ?? null;
  const dots = draw.filter((s) => s.arcs.length === 1 && s.pts.length === 1);
  return {
    draw,
    ring,
    arm,
    dots,
    pen: dots.length ? dots[dots.length - 1] : null,
    marker: dots.length > 1 ? dots[0] : null,
  };
}

const arc_xy = (stroke) =>
  stroke ? [stroke.arcs[0].x, stroke.arcs[0].y] : [NaN, NaN];
// ring radius, NaN when the frame drew no ring (unbound canvas / r = 0)
const ring_r = (frame) => (frame.ring ? frame.ring.arcs[0].r : NaN);

// ---- fresh FFI instances + the FFI clock model ------------------------------
// The column geometry pins need absolute t. A fresh module instance starts with
// t = 0, last = null, lastDraw = −∞; its first frame has dt 0 (t stays 0) and
// every later 34ms frame (> FRAME_MS) advances by min(34ms, 50ms)·SPEED. The
// contract mirrors exactly that — the same numbers the loop uses.
let scene_seq = 0;
async function column_scene(dial, kinds, opts = {}) {
  const rect = opts.rect ?? { width: RECT, height: RECT };
  unmount_all();
  const made = mount_all({ rect });
  scene_seq++;
  const f = await import("../src/fourier_toy_ffi.mjs?scene=" + scene_seq);
  const shape = puzzle.shape_of("quaver");
  f.canvas_shape(
    shape.centroid,
    shape.target,
    rows_of(shape.extras),
    shape.dial_max_r,
  );
  f.canvas_terms(dial, kinds);
  const clock = { t: 0, primed: false };
  tick(16); // bind, first frame: dt 0, t stays 0
  clock.primed = true;
  return {
    ffi: f,
    shape,
    made,
    clock,
    rect,
    space: Math.min(rect.width, rect.height) / 2,
  };
}

function advance(scene, ms = 34) {
  tick(ms);
  if (!scene.clock.primed) {
    scene.clock.primed = true;
    return scene.clock.t;
  }
  scene.clock.t =
    (scene.clock.t + Math.min(ms / 1000, 0.05) * SPEED) % 1;
  return scene.clock.t;
}

const DPR = 2;

console.log("S1 · cold load onto a board — sync arrives BEFORE the canvases mount");
{
  const setup = setup_of(); // quaver: DialP, DialR, DialK
  unmount_all(); // Lustre has not rendered yet
  sync_board(ffi, setup);
  check(
    "nothing scheduled pre-mount except the boot retry",
    raf_q.length === 1,
    "pending raf: " + raf_q.length,
  );
  check(
    "one boot retry pending (self-terminating, not a frame loop)",
    raf_q.length === 1,
    "pending raf: " + raf_q.length,
  );

  const made = mount_all(); // the first render mounts board + 3 columns
  tick(); // the retry binds and pumps
  for (let i = 0; i < 5; i++) tick(34); // let the frame loop draw

  const board = made[BOARD];
  const ops = board.getContext().ops;
  check("late boot paints: circles + pen arcs drawn", ops.arc >= 5, "arcs " + ops.arc);
  check("late boot paints: target + comet strokes", ops.stroke >= 13, "strokes " + ops.stroke);
  check("no NaN coordinates", ops.nan === 0, "nan " + ops.nan);
  check(
    "backing store sized on boot (dpr " + DPR + ")",
    board.width === 600 && board.height === 600,
    board.width + "x" + board.height,
  );
  check("target trace drawn (moveTo on target path)", ops.moveTo >= 13, "moveTo " + ops.moveTo);

  // Phase 2: the SAME retry binds the three column canvases, and the stashed
  // payload paints all of them (no re-push needed).
  for (let i = 0; i < COLS.length; i++) {
    const col = made[COLS[i]];
    check(
      COLS[i] + " binds on the same retry and paints (stashed payload)",
      col.width === 600 && col.getContext().ops.arc >= (i === 0 ? 3 : 2),
      col.width + "px, arcs " + col.getContext().ops.arc,
    );
  }
}

console.log("S2 · dial sync while booted — repaints on the live element");
{
  const setup = setup_of();
  const shape = puzzle.shape_of(setup.shape);
  const rows = step_state(shape, setup, puzzle.initial(shape, setup.patches), 0, -1); // phase −5°
  const before = ctx_of(BOARD).ops.arc;
  ffi.canvas_terms(rows_of(rows), kinds_of(setup));
  for (let i = 0; i < 3; i++) tick(34);
  const after = ctx_of(BOARD).ops.arc;
  check("dial change repaints (arcs grew)", after > before, before + " → " + after);
  check("still no NaN", ctx_of(BOARD).ops.nan === 0);
}

console.log("S3 · board→board — elements replaced between syncs rebind on the next sync");
{
  const old = {};
  for (const id of IDS) old[id] = el_of(id);
  const setup_next = setup_of();
  sync_board(ffi, setup_next); // sync runs pre-render: old elements still mounted
  const made = mount_all(); // the render REPLACED every canvas
  // the next sync (any dial press) must bind the new elements
  const shape = puzzle.shape_of(setup_next.shape);
  const rows = step_state(shape, setup_next, puzzle.initial(shape, setup_next.patches), 0, 1);
  ffi.canvas_terms(rows_of(rows), kinds_of(setup_next));
  for (let i = 0; i < 3; i++) tick(34);
  const new_board = made[BOARD];
  check(
    "new element bound (its backing store was reset)",
    new_board.width === 600,
    "width " + new_board.width,
  );
  check(
    "new element painted",
    new_board.getContext().ops.arc >= 5,
    "arcs " + new_board.getContext().ops.arc,
  );
  for (const id of COLS) {
    check(
      id + " rebound from the swapped element and painted",
      made[id].width === 600 && made[id].getContext().ops.arc >= 2,
      made[id].width + "px, arcs " + made[id].getContext().ops.arc,
    );
  }
  const frozen = old[BOARD].getContext().ops.arc;
  for (let i = 0; i < 3; i++) tick(34);
  check(
    "detached old elements no longer painted",
    old[BOARD].getContext().ops.arc === frozen,
    frozen + " → " + old[BOARD].getContext().ops.arc,
  );
}

console.log("S4 · home→board — payload stashed while unmounted survives to the late boot");
{
  unmount_all(); // home view rendered: no canvas
  for (let i = 0; i < 3; i++) tick(34); // the loop idles (nothing to assert yet)
  const setup = setup_of(); // quaver
  sync_board(ffi, setup); // hashchange sync runs pre-render: no canvas in the DOM
  // the live frame loop (drawing the previous, detached board) already holds
  // one pending raf; the retry must add exactly one more, once — never stack
  const pending_after_first_push = raf_q.length;
  sync_board(ffi, setup); // duplicate sync (e.g. re-render): retry stays single
  check(
    "one retry pending across pushes (no stacking)",
    raf_q.length === pending_after_first_push,
    "pending raf: " + pending_after_first_push + " → " + raf_q.length,
  );
  const made = mount_all(); // the render mounts the board + the columns
  tick(); // retry binds
  for (let i = 0; i < 5; i++) tick(34);
  const ops = made[BOARD].getContext().ops;
  check(
    "STASHED payload painted after late boot — no re-push needed",
    ops.arc >= 5 && ops.stroke >= 13,
    "arcs " + ops.arc + ", strokes " + ops.stroke,
  );
  check("no NaN after remount", ops.nan === 0, "nan " + ops.nan);
  for (const id of COLS) {
    check(
      id + " painted from the STASHED payload after the late boot",
      made[id].width === 600 && made[id].getContext().ops.arc >= 2,
      made[id].width + "px, arcs " + made[id].getContext().ops.arc,
    );
    check(id + " no NaN", made[id].getContext().ops.nan === 0);
  }
}

console.log("S5 · headless — no 2D context: app upright, no crash");
{
  unmount_all();
  mount_all({ headless: true }); // getContext returns null (jsdom w/o canvas pkg)
  let threw = null;
  try {
    const setup = setup_of();
    sync_board(ffi, setup);
    for (let i = 0; i < 3; i++) tick(34);
  } catch (err) {
    threw = err;
  }
  check("no throw with a null context (board + columns)", threw === null, String(threw));
}

console.log("S6 · quaver at truth — DPR transform, pen/comet lockstep, comet ≡ target");
{
  unmount_all();
  mount_all(); // rebind path (previous elements were headless)
  const setup = setup_of();
  const shape = puzzle.shape_of(setup.shape);
  ffi.canvas_shape(
    shape.centroid,
    shape.target,
    rows_of(shape.extras),
    shape.dial_max_r,
  );
  ffi.canvas_terms(
    rows_of(shape.dial), // TRUTH
    kinds_of(setup),
  );
  tick(); // bind + queue frame
  for (let i = 0; i < 3; i++) tick(34);
  const ops = ctx_of(BOARD).ops;
  check(
    "DPR transform applied (setTransform dpr·identity)",
    JSON.stringify(ops.setTransform_args) === "[2,0,0,2,0,0]",
    "got " + JSON.stringify(ops.setTransform_args),
  );
  // all geometry checks read the LAST draw only, split by role
  const last = board_frame();
  const pen = last.pen.pts[0]; // the pen dot's arc centre (the draw ends on it)
  const lastChunk = last.comet[last.comet.length - 1];
  const cometEnd = lastChunk.pts[lastChunk.pts.length - 1];
  const gap = dist(pen, cometEnd);
  check("pen sits on the comet's leading edge (≤ 1.3px)", gap <= TOL, gap.toFixed(2) + "px");
  // at truth the current synthesis IS the target synthesis: the comet must
  // overlay the dashed target (both are the same 512-sample full-synthesis
  // curve — extras rotating, not a constant offset)
  const target = last.target.pts;
  const comet = last.comet.flatMap((s) => s.pts);
  let maxDist = 0;
  for (const [x, y] of comet) {
    let best = Infinity;
    for (const [tx, ty] of target) {
      const d = Math.hypot(x - tx, y - ty);
      if (d < best) best = d;
    }
    if (best > maxDist) maxDist = best;
  }
  check(
    "comet overlays the dashed target at truth (full synthesis, rotating extras)",
    comet.length > 100 && maxDist <= 0.5,
    comet.length + " comet pts, max dist " + maxDist.toFixed(2) + "px",
  );
  // the pen must be ON the full-synthesis curve too (chain built from
  // dial + extras): its distance to the nearest target point is tiny
  let penDist = Infinity;
  for (const [tx, ty] of target) {
    const d = Math.hypot(pen[0] - tx, pen[1] - ty);
    if (d < penDist) penDist = d;
  }
  check(
    "pen sits on the full-synthesis curve (chain = dial + extras)",
    penDist <= 0.75,
    penDist.toFixed(2) + "px",
  );
  check("no NaN in the full-synthesis pass", ops.nan === 0, "nan " + ops.nan);
  // comet alpha ramp: the tail must stay readable (never below 40%),
  // the tip at 85%, dimmer toward the tail so motion still reads
  const cometA = last.comet.map((s) => s.alpha);
  const minA = Math.min(...cometA);
  const maxA = Math.max(...cometA);
  check(
    "comet tail never fades below 40% (full lap readable)",
    minA >= 0.4,
    "min " + minA.toFixed(3),
  );
  check(
    "comet tip at 85%, gradient tail→tip",
    maxA <= 0.85 + 1e-9 && cometA[0] < cometA[cometA.length - 1],
    "max " + maxA.toFixed(3) + ", head " + cometA[0] + " tail " + cometA[cometA.length - 1],
  );
}

console.log("S7 · ordinal ink on the board — chain position decides the colour, both modes");
{
  // Ordinal ink (PLAN-dial-columns §3): term 0 red, term 1 yellow, term 2 blue
  // — always. The standard arrangement makes ordinal ≡ kind visually; the
  // contract is the chain position. Extras stay the neutral wash.
  // NOTE the light yellow: the brief's print-yellow #c9a411 measures 2.31:1 on
  // the white card (below the 3:1 non-text floor), so light mode uses #8a6d00
  // (4.75:1 on paper) — a darkened print-yellow.
  const LIGHT = {
    ink: ["#c8321e", "#8a6d00", "#1f5fae"],
    neutral: "rgba(17,17,17,0.18)",
    target: "rgba(17,17,17,0.35)",
    on: "#111",
  };
  const DARK = {
    ink: ["#e05a4a", "#ffd93d", "#5aa0e8"],
    neutral: "rgba(245,245,245,0.10)",
    target: "rgba(245,245,245,0.25)",
    on: "#f5f5f5",
  };
  unmount_all();
  mount_all();
  sync_board(ffi, setup_of());
  for (let i = 0; i < 5; i++) tick(34);

  const light = board_frame();
  const lc = light.circles; // chain order: the 3 dial terms, then the extras
  check(
    "light: term 0's orbit inked in ordinal 0 (red)",
    lc[0]?.style === LIGHT.ink[0],
    "term 0 style " + lc[0]?.style,
  );
  check(
    "light: term 1's orbit inked in ordinal 1 (the darkened yellow)",
    lc[1]?.style === LIGHT.ink[1],
    "term 1 style " + lc[1]?.style,
  );
  check(
    "light: term 2's orbit inked in ordinal 2 (blue)",
    lc[2]?.style === LIGHT.ink[2],
    "term 2 style " + lc[2]?.style,
  );
  check(
    "light: the first extra keeps the neutral wash (not an ordinal ink)",
    lc[3]?.style === LIGHT.neutral,
    "extra 0 style " + lc[3]?.style,
  );
  check(
    "light: the comet trace rides the on-colour",
    light.comet.length === COMET_CHUNKS && light.comet.every((s) => s.style === LIGHT.on),
    light.comet.map((s) => s.style).join(","),
  );
  check(
    "light: the pen is the on-colour, bolder at 2.6",
    light.pen.style === LIGHT.on && light.pen.width === 2.6,
    light.pen.style + " @ " + light.pen.width,
  );
  check(
    "light: the dashed target is the faint ink (colors ride along)",
    light.target.style === LIGHT.target,
    String(light.target.style),
  );

  ffi.canvas_theme(true); // the same payload, the other mode's palette
  for (let i = 0; i < 5; i++) tick(34);
  const dark = board_frame();
  const dc = dark.circles;
  check(
    "dark: term 0's orbit inked in ordinal 0 (red)",
    dc[0]?.style === DARK.ink[0],
    "term 0 style " + dc[0]?.style,
  );
  check(
    "dark: term 1's orbit inked in ordinal 1 (yellow)",
    dc[1]?.style === DARK.ink[1],
    "term 1 style " + dc[1]?.style,
  );
  check(
    "dark: term 2's orbit inked in ordinal 2 (blue)",
    dc[2]?.style === DARK.ink[2],
    "term 2 style " + dc[2]?.style,
  );
  check(
    "dark: the first extra keeps the neutral wash",
    dc[3]?.style === DARK.neutral,
    "extra 0 style " + dc[3]?.style,
  );
  check(
    "dark: the comet trace rides the on-colour",
    dark.comet.length === COMET_CHUNKS && dark.comet.every((s) => s.style === DARK.on),
    dark.comet.map((s) => s.style).join(","),
  );
  check(
    "dark: the dashed target is the faint ink",
    dark.target.style === DARK.target,
    String(dark.target.style),
  );
}

console.log("S8 · the three column canvases bind like the board");
{
  const setup = setup_of();
  const shape = puzzle.shape_of(setup.shape);

  // (a) cold load: no canvas in the DOM at sync time, payload stashed
  unmount_all();
  sync_board(ffi, setup);
  const made = mount_all();
  tick();
  for (let i = 0; i < 3; i++) tick(34);
  for (const id of COLS) {
    const frame = column_frame(id);
    check(
      "cold load: " + id + " binds late and paints the stashed payload",
      made[id].width === 600 && frame.ring !== null,
      made[id].width + "px, ring " + (frame.ring !== null),
    );
  }

  // (b) a DOM without the columns (pre-Phase-3): the board binds, the missing
  // canvases are skipped — never an error — and they bind on a later push
  unmount_all();
  mounted.set(BOARD, make_el()); // board only
  let threw = null;
  try {
    sync_board(ffi, setup);
    for (let i = 0; i < 3; i++) tick(34);
  } catch (err) {
    threw = err;
  }
  check(
    "board-only DOM: missing column canvases are skipped, never an error",
    threw === null && ctx_of(BOARD).ops.arc >= 5,
    String(threw),
  );
  const late = mount_all(); // the Phase-3 view renders the columns
  const rows = step_state(shape, setup, puzzle.initial(shape, setup.patches), 2, -1);
  ffi.canvas_terms(rows_of(rows), kinds_of(setup));
  for (let i = 0; i < 3; i++) tick(34);
  for (const id of COLS) {
    check(
      "columns bind on the next payload once they mount (" + id + ")",
      late[id].width === 600 && late[id].getContext().ops.arc >= 2,
      late[id].width + "px, arcs " + late[id].getContext().ops.arc,
    );
  }

  // (c) an element swap rebinds all four on the next sync
  const old = {};
  for (const id of IDS) old[id] = el_of(id);
  sync_board(ffi, setup);
  const swapped = mount_all();
  ffi.canvas_terms(rows_of(shape.dial), kinds_of(setup));
  for (let i = 0; i < 3; i++) tick(34);
  for (const id of COLS) {
    check(
      "swap: " + id + " rebinds and paints the new element",
      swapped[id].width === 600 && swapped[id].getContext().ops.arc >= 2,
      swapped[id].width + "px, arcs " + swapped[id].getContext().ops.arc,
    );
  }
  const frozen = old["col-1"].getContext().ops.arc;
  for (let i = 0; i < 3; i++) tick(34);
  check(
    "swap: detached old column no longer painted",
    old["col-1"].getContext().ops.arc === frozen,
    frozen + " → " + old["col-1"].getContext().ops.arc,
  );
}

console.log("S9 · fixed rings — phase and k at 0.5 × the column's space (ratio, not px)");
{
  const shape = puzzle.shape_of("quaver");
  const maxR = shape.dial_max_r;
  const dial = [
    [-1, maxR, 30.0],
    [1, maxR, 120.0],
    [-3, maxR, 200.0],
  ];
  const kinds = [KIND_PHASE, KIND_RADIUS, KIND_K];

  const scene = await column_scene(dial, kinds);
  const phase = column_frame("col-0");
  const kcol = column_frame("col-2");
  check(
    "phase column ring radius = 0.5 × space",
    phase.ring !== null && Math.abs(phase.ring.arcs[0].r - 0.5 * scene.space) <= TOL,
    "r " + phase.ring?.arcs[0].r + ", expected " + 0.5 * scene.space,
  );
  check(
    "k column ring radius = 0.5 × space",
    kcol.ring !== null && Math.abs(kcol.ring.arcs[0].r - 0.5 * scene.space) <= TOL,
    "r " + kcol.ring?.arcs[0].r + ", expected " + 0.5 * scene.space,
  );
  check(
    "rings are centred in the column canvas",
    phase.ring !== null &&
      Math.abs(phase.ring.arcs[0].x - scene.rect.width / 2) <= TOL &&
      Math.abs(phase.ring.arcs[0].y - scene.rect.height / 2) <= TOL,
    JSON.stringify(phase.ring?.arcs[0]),
  );

  // the same ratio on a different box (proves the scale is a ratio, not px)
  const rect = { width: 240, height: 160 };
  const small = await column_scene(dial, kinds, { rect });
  const small_phase = column_frame("col-0");
  const small_k = column_frame("col-2");
  check(
    "ratio holds on a non-square 240×160 box (space = min(w,h)/2)",
    small_phase.ring !== null &&
      Math.abs(small_phase.ring.arcs[0].r - 0.5 * small.space) <= TOL &&
      small_k.ring !== null &&
      Math.abs(small_k.ring.arcs[0].r - 0.5 * small.space) <= TOL,
    "phase " + small_phase.ring?.arcs[0].r + ", k " + small_k.ring?.arcs[0].r +
      ", expected " + 0.5 * small.space,
  );
}

console.log("S10 · radius ring is linear — 0 empty, max = phase ring, 2·max = full space");
{
  const shape = puzzle.shape_of("quaver");
  const maxR = shape.dial_max_r;
  const kinds = [KIND_PHASE, KIND_RADIUS, KIND_K];
  const dial_at = (r) => [
    [-1, maxR, 30.0],
    [1, r, 120.0],
    [-3, maxR, 200.0],
  ];

  const scene = await column_scene(dial_at(maxR), kinds);
  const phaseR = ring_r(column_frame("col-0"));
  const atMax = column_frame("col-1");
  check(
    "r = max: radius ring equals the phase ring (100% = half the space)",
    atMax.ring !== null && Math.abs(atMax.ring.arcs[0].r - phaseR) <= TOL,
    "radius " + atMax.ring?.arcs[0].r + ", phase " + phaseR,
  );

  // r = 0: NOTHING for the radius column — no ring, no arm, no pen (op-count 0)
  scene.ffi.canvas_terms(dial_at(0.0), kinds);
  const before = ctx_of("col-1").ops;
  const beforeCounts = {
    arc: before.arc,
    moveTo: before.moveTo,
    lineTo: before.lineTo,
    stroke: before.stroke,
  };
  advance(scene);
  const empty = column_frame("col-1");
  const ops = ctx_of("col-1").ops;
  check(
    "r = 0: no ring, no arm, no pen — op-count zero for that column",
    empty.draw.length === 0 &&
      ops.arc === beforeCounts.arc &&
      ops.moveTo === beforeCounts.moveTo &&
      ops.lineTo === beforeCounts.lineTo &&
      ops.stroke === beforeCounts.stroke,
    "strokes " + empty.draw.length +
      ", deltas arc " + (ops.arc - beforeCounts.arc) +
      ", moveTo " + (ops.moveTo - beforeCounts.moveTo) +
      ", lineTo " + (ops.lineTo - beforeCounts.lineTo) +
      ", stroke " + (ops.stroke - beforeCounts.stroke),
  );
  check(
    "r = 0: the other columns keep drawing (the clock is not skipped)",
    column_frame("col-0").draw.length > 0 && column_frame("col-2").draw.length > 0,
  );

  // r = 0.5·max: quarter space
  scene.ffi.canvas_terms(dial_at(0.5 * maxR), kinds);
  advance(scene);
  const half = column_frame("col-1");
  check(
    "r = 0.5·max: ring radius = 0.25 × space",
    half.ring !== null && Math.abs(half.ring.arcs[0].r - 0.25 * scene.space) <= TOL,
    "r " + half.ring?.arcs[0].r + ", expected " + 0.25 * scene.space,
  );

  // r = 2·max (the 200% ceiling): the ring fills the space exactly
  scene.ffi.canvas_terms(dial_at(2.0 * maxR), kinds);
  advance(scene);
  const ceiling = column_frame("col-1");
  check(
    "r = 2·max: ring radius = the full space (diameter = the box)",
    ceiling.ring !== null && Math.abs(ceiling.ring.arcs[0].r - scene.space) <= TOL,
    "r " + ceiling.ring?.arcs[0].r + ", expected " + scene.space,
  );
}

console.log("S11 · arm matches the canvas chain — 2πkt + φ on the board's clock");
{
  const shape = puzzle.shape_of("quaver");
  const maxR = shape.dial_max_r;
  const dial = [
    [-1, maxR, 20.0],
    [1, maxR, 200.0],
    [-3, maxR, 80.0],
  ];
  const kinds = [KIND_PHASE, KIND_RADIUS, KIND_K];
  const scene = await column_scene(dial, kinds);

  // capture each probe's frames AT its t: the element always holds the most
  // recent frame, so reading after the loop would compare every probe against
  // the last one
  const probes = [];
  const capture = (label) => {
    probes.push({
      t: scene.clock.t,
      label,
      frames: COLS.map((id) => column_frame(id)),
    });
  };
  capture("t=0");
  for (const n of [1, 5, 10]) {
    for (let i = 0; i < n; i++) advance(scene);
    capture("t=" + scene.clock.t.toFixed(5));
  }

  for (const probe of probes) {
    for (let i = 0; i < COLS.length; i++) {
      const frame = probe.frames[i];
      const cx = scene.rect.width / 2;
      const cy = scene.rect.height / 2;
      const ringR = ring_r(frame);
      const expected = tip_at(cx, cy, ringR, dial[i][0], dial[i][2], probe.t);
      const penAt = frame.pen ? arc_xy(frame.pen) : [NaN, NaN];
      const armTip = frame.arm ? frame.arm.pts[frame.arm.pts.length - 1] : [NaN, NaN];
      const armStart = frame.arm ? frame.arm.pts[0] : [NaN, NaN];
      check(
        COLS[i] + " @ " + probe.label + ": pen sits on the term's chain point",
        dist(penAt, expected) <= TOL,
        "pen " + penAt.map((v) => v.toFixed(2)) + " vs " + expected.map((v) => v.toFixed(2)) +
          " (d " + dist(penAt, expected).toFixed(2) + "px)",
      );
      check(
        COLS[i] + " @ " + probe.label + ": arm runs centre → tip",
        dist(armStart, [cx, cy]) <= TOL && dist(armTip, expected) <= TOL,
        "start " + armStart.map((v) => v.toFixed(2)) + ", tip " + armTip.map((v) => v.toFixed(2)),
      );
    }
  }
}

console.log("S12 · start-marker — a lone dot on the phase ring, where φ lands");
{
  const shape = puzzle.shape_of("quaver");
  const maxR = shape.dial_max_r;
  const dial = [
    [-1, maxR, 200.0],
    [1, maxR, 120.0],
    [-3, maxR, 80.0],
  ];
  const kinds = [KIND_PHASE, KIND_RADIUS, KIND_K];
  const scene = await column_scene(dial, kinds);
  const cx = scene.rect.width / 2;
  const cy = scene.rect.height / 2;

  const frame = column_frame("col-0");
  const ringR = ring_r(frame);
  const expected = marker_at(cx, cy, ringR, dial[0][2]);
  check(
    "phase column draws a marker dot at (cx + R·cos φ, cy + R·sin φ)",
    frame.marker !== null && dist(arc_xy(frame.marker), expected) <= TOL,
    "marker " + (frame.marker ? arc_xy(frame.marker).map((v) => v.toFixed(2)) : null) +
      " vs " + expected.map((v) => v.toFixed(2)),
  );
  check(
    "the marker is a dot without an arm (arc only, no line)",
    frame.marker !== null &&
      frame.marker.arcs.length === 1 &&
      frame.marker.pts.length === 1,
    frame.marker ? frame.marker.arcs.length + " arcs, " + frame.marker.pts.length + " pts" : "none",
  );
  const markerBefore = arc_xy(frame.marker);
  for (let i = 0; i < 3; i++) advance(scene);
  const later = column_frame("col-0");
  check(
    "the marker is static (reads φ, never t)",
    dist(arc_xy(later.marker), markerBefore) <= 1e-9,
    "moved " + dist(arc_xy(later.marker), markerBefore) + "px",
  );
  check(
    "the pen is distinguishable from the marker once the arm turns",
    dist(arc_xy(later.pen), arc_xy(later.marker)) > 1.0,
    "separation " + dist(arc_xy(later.pen), arc_xy(later.marker)).toFixed(2) + "px",
  );
}

console.log("S13 · k = 0 freezes — two frames at different t draw the identical arm angle");
{
  const shape = puzzle.shape_of("quaver");
  const maxR = shape.dial_max_r;
  const dial = [
    [1, maxR, 40.0],
    [1, maxR, 140.0],
    [0, maxR, 250.0], // the k column's term: frozen
  ];
  const kinds = [KIND_PHASE, KIND_RADIUS, KIND_K];
  const scene = await column_scene(dial, kinds);

  const first = column_frame("col-2");
  const movingFirst = column_frame("col-0");
  const penAt = arc_xy(first.pen);
  const expected = tip_at(
    scene.rect.width / 2,
    scene.rect.height / 2,
    ring_r(first),
    0,
    250.0,
    scene.clock.t,
  );
  check(
    "k = 0: the arm points at the dialed phase (no rotation)",
    dist(penAt, expected) <= TOL,
    "d " + dist(penAt, expected).toFixed(2) + "px",
  );
  for (let i = 0; i < 5; i++) advance(scene);
  const second = column_frame("col-2");
  check(
    "k = 0: two frames at different t draw the identical angle",
    dist(arc_xy(second.pen), penAt) <= 1e-9,
    "moved " + dist(arc_xy(second.pen), penAt) + "px",
  );
  check(
    "k ≠ 0 columns keep rotating on the same clock",
    dist(arc_xy(column_frame("col-0").pen), arc_xy(movingFirst.pen)) > 1.0,
    "moved " + dist(arc_xy(column_frame("col-0").pen), arc_xy(movingFirst.pen)).toFixed(2) + "px",
  );
}

console.log("S14 · ordinal ink on the columns — index 0/1/2 in BOTH themes");
{
  const LIGHT_INK = ["#c8321e", "#8a6d00", "#1f5fae"];
  const DARK_INK = ["#e05a4a", "#ffd93d", "#5aa0e8"];
  const shape = puzzle.shape_of("quaver");
  const maxR = shape.dial_max_r;
  const dial = [
    [-1, maxR, 20.0],
    [1, maxR, 200.0],
    [-3, maxR, 80.0],
  ];
  const kinds = [KIND_PHASE, KIND_RADIUS, KIND_K];
  const scene = await column_scene(dial, kinds);

  for (let i = 0; i < COLS.length; i++) {
    const frame = column_frame(COLS[i]);
    check(
      "light: " + COLS[i] + " ring inked in ordinal " + i,
      frame.ring?.style === LIGHT_INK[i],
      String(frame.ring?.style),
    );
    check(
      "light: " + COLS[i] + " arm and pen inked in ordinal " + i,
      frame.arm?.style === LIGHT_INK[i] && frame.pen?.style === LIGHT_INK[i],
      "arm " + frame.arm?.style + ", pen " + frame.pen?.style,
    );
  }

  scene.ffi.canvas_theme(true);
  advance(scene);
  for (let i = 0; i < COLS.length; i++) {
    const frame = column_frame(COLS[i]);
    check(
      "dark: " + COLS[i] + " ring inked in ordinal " + i,
      frame.ring?.style === DARK_INK[i],
      String(frame.ring?.style),
    );
    check(
      "dark: " + COLS[i] + " arm and pen inked in ordinal " + i,
      frame.arm?.style === DARK_INK[i] && frame.pen?.style === DARK_INK[i],
      "arm " + frame.arm?.style + ", pen " + frame.pen?.style,
    );
  }
}

console.log("S15 · one clock — all four canvases repaint from the same 30fps tick");
{
  const shape = puzzle.shape_of("quaver");
  const maxR = shape.dial_max_r;
  const dial = [
    [-1, maxR, 20.0],
    [1, maxR, 200.0],
    [-3, maxR, 80.0],
  ];
  const kinds = [KIND_PHASE, KIND_RADIUS, KIND_K];
  const scene = await column_scene(dial, kinds);

  // same tick, four repaints: no per-canvas RAF pump
  const clears = {};
  for (const id of IDS) clears[id] = ctx_of(id).ops.clearRect;
  advance(scene);
  for (const id of IDS) {
    check(
      id + " repaints from the same RAF tick",
      ctx_of(id).ops.clearRect === clears[id] + 1,
      clears[id] + " → " + ctx_of(id).ops.clearRect,
    );
  }

  // 30fps cap: 16ms ticks do not draw; the third (48ms) does
  const capped = ctx_of(BOARD).ops.clearRect;
  tick(16);
  tick(16);
  check(
    "30fps cap: two 16ms frames do not repaint",
    ctx_of(BOARD).ops.clearRect === capped,
    "clears " + capped + " → " + ctx_of(BOARD).ops.clearRect,
  );
  tick(16);
  check(
    "30fps cap: the third 16ms frame (48ms) repaints",
    ctx_of(BOARD).ops.clearRect === capped + 1,
    "clears " + capped + " → " + ctx_of(BOARD).ops.clearRect,
  );

  // dedupe: identical terms skip the O(STEPS × terms) rebuild — no trig at all
  const real_cos = Math.cos;
  const real_sin = Math.sin;
  let trig = 0;
  Math.cos = (x) => {
    trig++;
    return real_cos(x);
  };
  Math.sin = (x) => {
    trig++;
    return real_sin(x);
  };
  scene.ffi.canvas_terms(
    dial.map((r) => [r[0], r[1], r[2]]),
    kinds,
  ); // identical payload
  const rebuilt_twice = trig;
  scene.ffi.canvas_terms(
    [
      [dial[0][0], dial[0][1], dial[0][2] + 5.0],
      dial[1],
      dial[2],
    ],
    kinds,
  );
  const rebuilt_changed = trig - rebuilt_twice;
  Math.cos = real_cos;
  Math.sin = real_sin;
  check(
    "dedupe: unchanged terms skip the rebuild (0 trig calls)",
    rebuilt_twice === 0,
    "trig " + rebuilt_twice,
  );
  check(
    "dedupe: changed terms DO rebuild (the counter works)",
    rebuilt_changed > 0,
    "trig " + rebuilt_changed,
  );

  // DPR ≤ 2: a 3× device still paints a 2× backing store
  globalThis.window.devicePixelRatio = 3;
  const hidpi = await column_scene(dial, kinds);
  for (const id of IDS) {
    const el = hidpi.made[id];
    const ops = el.getContext().ops;
    check(
      id + " clamps DPR 3 → 2 (backing store " + RECT * 2 + "px)",
      el.width === RECT * 2 &&
        JSON.stringify(ops.setTransform_args) === "[2,0,0,2,0,0]",
      el.width + "px, transform " + JSON.stringify(ops.setTransform_args),
    );
  }
  globalThis.window.devicePixelRatio = 2;
}

console.log("");
console.log(passed + "/" + (passed + failed) + " checks passed");
if (failed > 0) process.exit(1);
