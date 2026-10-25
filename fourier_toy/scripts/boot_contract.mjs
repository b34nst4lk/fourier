// Boot/payload behavior contract for the v2 canvas loop (pure Node, no DOM
// deps — house bench pattern from fourier_sketch/scripts/bench_render.mjs).
//
// The premise, verified in Lustre's runtime source (runtime/client/
// runtime.ffi.mjs, constructor): init effects run BEFORE the first render —
//   this.#handleEffects(effects);   // ← sync_effect fires here
//   this.#render();                 // ← the canvas mounts here
// and hashchange dispatches run effects synchronously while renders are
// RAF-deferred — so a board sync can also arrive before its canvas mounts.
//
// Contract: the payload pushed by a pre-mount sync must SURVIVE until the
// canvas exists; a late boot must paint it. Payloads are stashed
// unconditionally and boot (canvas binding) is orthogonal — the sibling
// fourier_sketch_ffi pattern proven in production.
//
// Run: node scripts/boot_contract.mjs

import * as ffi from "../src/fourier_toy_ffi.mjs";
import * as shapes from "../build/dev/javascript/fourier_toy/fourier_toy/shapes.mjs";
import * as puzzle from "../build/dev/javascript/fourier_toy/fourier_toy/puzzle.mjs";

// ---- stub DOM (bench_render.mjs pattern) ------------------------------------
//
// The registry models what Lustre has mounted: null = no canvas in the DOM
// (home view, or a board sync that ran before the render committed).
let registry = null;

function make_ctx() {
  const ops = {
    arc: 0,
    moveTo: 0,
    lineTo: 0,
    stroke: 0,
    clearRect: 0,
    nan: 0,
    setTransform_args: null, // last setTransform() call (DPR contract)
    pen: null, // last arc() center = the pen tip (draws end with the pen)
    // one frame's strokes, grouped at the frame's clearRect:
    // [{ pts, style, width, alpha, arcs }, ...] in draw order
    draws: [],
    stroke_alphas: [], // globalAlpha at each stroke (comet ramp contract)
  };
  let seg = []; // coords accumulated since the last stroke
  let seg_arcs = 0; // arc() calls since the last stroke (circle vs arm)
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
    arc: (x, y, _r) => {
      count("arc");
      seg_arcs++;
      push(x, y);
      ops.pen = [x, y];
    },
    stroke: () => {
      ops.stroke++;
      if (ops.draws.length === 0) ops.draws.push([]);
      ops.draws[ops.draws.length - 1].push({
        pts: seg,
        style: curStyle,
        width: curWidth,
        alpha: curAlpha,
        arcs: seg_arcs,
      });
      ops.stroke_alphas.push(curAlpha);
      seg = [];
      seg_arcs = 0;
    },
  };
}

let el_seq = 0;
function make_el(headless = false) {
  el_seq++;
  const ctx = headless ? null : make_ctx(); // ONE stable ctx per element
  return {
    id: "el" + el_seq,
    width: 0,
    height: 0,
    getBoundingClientRect: () => ({ width: 300, height: 300, left: 0, top: 0 }),
    getContext: () => ctx,
  };
}

globalThis.document = {
  body: { getAttribute: () => "light" },
  getElementById: () => registry,
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

// The last frame's strokes, split by draw-order ROLE rather than by a fixed
// offset — the ink pass now strokes each chain row separately (so a row can
// carry its own colour), which makes the row count geometry-dependent. The
// roles are: the dashed target first, one circle stroke per visible row, one
// arm stroke per visible row, 12 comet chunks, the pen last.
const COMET_CHUNKS = 12; // fourier_toy_ffi.mjs CHUNKS
function last_draw(ops) {
  const draw = ops.draws[ops.draws.length - 1];
  return {
    target: draw[0],
    circles: draw.filter((s) => s.arcs === 1 && s.pts.length === 2),
    links: draw.filter((s) => s.arcs === 0 && s.pts.length === 2),
    comet: draw.slice(draw.length - 1 - COMET_CHUNKS, draw.length - 1),
    pen: draw[draw.length - 1],
  };
}

// the app is single-puzzle: scenarios drive THE shipped puzzle (quaver) via
// the public accessor. setups/find are private — not contract surface.
const setup_of = () => puzzle.quaver_setup();

// The exact pushes ffi.gleam makes for a Board page: canvas_shape(shape),
// then canvas_terms(state, dials). The Gleam side pre-maps BOTH TermState
// lists to #(k, r, phase_deg) tuples (ffi.gleam `row`) and the arrangement to
// its kind codes (puzzle.kind_code) — replicate both here. The canvas needs the
// kinds because the ink follows the KIND (the arrangement is data).
const kinds_of = (setup) => Array.from(setup.dials, (kind) => puzzle.kind_code(kind));

function sync_board(setup) {
  const shape = puzzle.shape_of(setup.shape);
  const extras = Array.from(shape.extras, (t) => [t.k, t.r, t.phase_deg]);
  ffi.canvas_shape(shape.centroid, shape.target, extras);
  const state = puzzle.initial(shape, setup.patches);
  ffi.canvas_terms(Array.from(state, (s) => [s.k, s.r, s.phase_deg]), kinds_of(setup));
  return { shape, state };
}

function step_state(shape, setup, state, slot, dir) {
  const kinds = Array.from(setup.dials);
  const rows = Array.from(state);
  rows[slot] = puzzle.step(kinds[slot], rows[slot], dir, shape.dial_max_r);
  return rows;
}

const DPR = 2;

console.log("S1 · cold load onto a board — sync arrives BEFORE the canvas mounts");
{
  const setup = setup_of(); // quaver: DialP, DialR, DialK, DialFixed
  registry = null; // Lustre has not rendered yet
  const { shape, state } = sync_board(setup);
  check("nothing scheduled pre-mount except the boot retry", raf_q.length === 1, "pending raf: " + raf_q.length);
  check(
    "one boot retry pending (self-terminating, not a frame loop)",
    raf_q.length === 1,
    "pending raf: " + raf_q.length,
  );

  registry = make_el(); // the first render mounts the canvas
  tick(); // the retry binds and pumps
  for (let i = 0; i < 5; i++) tick(34); // let the frame loop draw

  const el = registry;
  const ops = el.getContext().ops;
  check("late boot paints: circles + pen arcs drawn", ops.arc >= 5, "arcs " + ops.arc);
  check("late boot paints: target + comet strokes", ops.stroke >= 13, "strokes " + ops.stroke);
  check("no NaN coordinates", ops.nan === 0, "nan " + ops.nan);
  check(
    "backing store sized on boot (dpr " + DPR + ")",
    el.width === 600 && el.height === 600,
    el.width + "x" + el.height,
  );
  check("target trace drawn (moveTo on target path)", ops.moveTo >= 13, "moveTo " + ops.moveTo);
}

console.log("S2 · dial sync while booted — repaints on the live element");
{
  const setup = setup_of();
  const shape = puzzle.shape_of(setup.shape);
  const rows = step_state(shape, setup, puzzle.initial(shape, setup.patches), 0, -1); // phase −5°
  const before = registry.getContext().ops.arc;
  ffi.canvas_terms(rows.map((s) => [s.k, s.r, s.phase_deg]), kinds_of(setup));
  for (let i = 0; i < 3; i++) tick(34);
  const after = registry.getContext().ops.arc;
  check("dial change repaints (arcs grew)", after > before, before + " → " + after);
  check("still no NaN", registry.getContext().ops.nan === 0);
}

console.log("S3 · board→board — element replaced between syncs rebinds on the next sync");
{
  const old_el = registry;
  const setup_next = setup_of();
  sync_board(setup_next); // sync runs pre-render: old element still mounted
  registry = make_el(); // the render REPLACED the canvas element
  const new_el = registry;
  // the next sync (any dial press) must bind the new element
  const shape = puzzle.shape_of(setup_next.shape);
  const rows = step_state(shape, setup_next, puzzle.initial(shape, setup_next.patches), 0, 1);
  ffi.canvas_terms(rows.map((s) => [s.k, s.r, s.phase_deg]), kinds_of(setup_next));
  for (let i = 0; i < 3; i++) tick(34);
  check(
    "new element bound (its backing store was reset)",
    new_el.width === 600,
    "width " + new_el.width,
  );
  check("new element painted", new_el.getContext().ops.arc >= 5, "arcs " + new_el.getContext().ops.arc);
  const frozen = old_el.getContext().ops.arc;
  for (let i = 0; i < 3; i++) tick(34);
  check(
    "detached old element no longer painted",
    old_el.getContext().ops.arc === frozen,
    frozen + " → " + old_el.getContext().ops.arc,
  );
}

console.log("S4 · home→board — payload stashed while unmounted survives to the late boot");
{
  registry = null; // home view rendered: no canvas
  for (let i = 0; i < 3; i++) tick(34); // the loop idles (nothing to assert yet)
  const setup = setup_of(); // quaver
  sync_board(setup); // hashchange sync runs pre-render: no canvas in the DOM
  // the live frame loop (drawing the previous, detached board) already holds
  // one pending raf; the retry must add exactly one more, once — never stack
  const pending_after_first_push = raf_q.length;
  sync_board(setup); // duplicate sync (e.g. re-render): retry stays single
  check(
    "one retry pending across pushes (no stacking)",
    raf_q.length === pending_after_first_push,
    "pending raf: " + pending_after_first_push + " → " + raf_q.length,
  );
  registry = make_el(); // the render mounts the board canvas
  tick(); // retry binds
  for (let i = 0; i < 5; i++) tick(34);
  const ops = registry.getContext().ops;
  check(
    "STASHED payload painted after late boot — no re-push needed",
    ops.arc >= 5 && ops.stroke >= 13,
    "arcs " + ops.arc + ", strokes " + ops.stroke,
  );
  check("no NaN after remount", ops.nan === 0, "nan " + ops.nan);
}

console.log("S5 · headless — no 2D context: app upright, no crash");
{
  registry = make_el(true); // getContext returns null (jsdom w/o canvas pkg)
  let threw = null;
  try {
    const setup = setup_of();
    sync_board(setup);
    for (let i = 0; i < 3; i++) tick(34);
  } catch (err) {
    threw = err;
  }
  check("no throw with a null context", threw === null, String(threw));
}

console.log("S6 · quaver at truth — DPR transform, pen/comet lockstep, comet ≡ target");
{
  registry = make_el(); // rebind path (previous element was headless)
  const setup = setup_of(); // quaver: 4 dial terms + 25 rotating extras
  const shape = puzzle.shape_of(setup.shape);
  const extras = Array.from(shape.extras, (t) => [t.k, t.r, t.phase_deg]);
  ffi.canvas_shape(shape.centroid, shape.target, extras);
  ffi.canvas_terms(
    Array.from(shape.dial, (s) => [s.k, s.r, s.phase_deg]), // TRUTH
    kinds_of(setup),
  );
  tick(); // bind + queue frame
  tick(34, 3); // draws at t = 0.00625 + k·0.00425
  const ops = registry.getContext().ops;
  check(
    "DPR transform applied (setTransform dpr·identity)",
    JSON.stringify(ops.setTransform_args) === "[2,0,0,2,0,0]",
    "got " + JSON.stringify(ops.setTransform_args),
  );
  // all geometry checks read the LAST draw only, split by role
  // (target, per-row circles, per-row arms, 12 comet chunks, pen)
  const last = last_draw(ops);
  const pen = last.pen.pts[0]; // the pen dot's arc centre (the draw ends on it)
  const lastChunk = last.comet[last.comet.length - 1];
  const cometEnd = lastChunk.pts[lastChunk.pts.length - 1];
  const gap = Math.hypot(pen[0] - cometEnd[0], pen[1] - cometEnd[1]);
  check(
    "pen sits on the comet's leading edge (≤ 1.3px)",
    gap <= 1.3,
    gap.toFixed(2) + "px",
  );
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

console.log("S7 · kind ink — the arrangement decides the colours, in both modes");
{
  // The toy's one shipped arrangement: slot 0 phase (red), 1 radius (yellow),
  // 2 k (blue), 3 fixed (neutral). The colour follows the KIND, not the slot
  // index — this scenario reads the ink off the circles pass, row by row.
  // NOTE the light yellow: the brief's print-yellow #c9a411 measures 2.31:1 on
  // the white card (below the 3:1 non-text floor, and far below 4.5:1 text),
  // so light mode uses #8a6d00 (4.75:1 on paper) — a darkened print-yellow.
  const LIGHT = {
    phase: "#c8321e",
    radius: "#8a6d00",
    k: "#1f5fae",
    neutral: "rgba(17,17,17,0.18)",
    target: "rgba(17,17,17,0.35)",
    on: "#111",
  };
  const DARK = {
    phase: "#e05a4a",
    radius: "#ffd93d",
    k: "#5aa0e8",
    neutral: "rgba(245,245,245,0.10)",
    target: "rgba(245,245,245,0.25)",
    on: "#f5f5f5",
  };
  registry = make_el();
  const setup = setup_of();
  sync_board(setup);
  for (let i = 0; i < 5; i++) tick(34);

  const light = last_draw(registry.getContext().ops);
  const lc = light.circles; // chain order: slot 0, 1, 2, 3, then the extras
  check(
    "light: phase slot's orbit inked in the phase red",
    lc[0]?.style === LIGHT.phase,
    "slot 0 style " + lc[0]?.style,
  );
  check(
    "light: radius slot's orbit inked in the (darkened) radius yellow",
    lc[1]?.style === LIGHT.radius,
    "slot 1 style " + lc[1]?.style,
  );
  check(
    "light: k slot's orbit inked in the k blue",
    lc[2]?.style === LIGHT.k,
    "slot 2 style " + lc[2]?.style,
  );
  check(
    "light: the fixed slot keeps the neutral wash (not a movable ink)",
    lc[3]?.style === LIGHT.neutral,
    "slot 3 style " + lc[3]?.style,
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
  const dark = last_draw(registry.getContext().ops);
  const dc = dark.circles;
  check(
    "dark: phase slot's orbit inked in the phase red",
    dc[0]?.style === DARK.phase,
    "slot 0 style " + dc[0]?.style,
  );
  check(
    "dark: radius slot's orbit inked in the radius yellow",
    dc[1]?.style === DARK.radius,
    "slot 1 style " + dc[1]?.style,
  );
  check(
    "dark: k slot's orbit inked in the k blue",
    dc[2]?.style === DARK.k,
    "slot 2 style " + dc[2]?.style,
  );
  check(
    "dark: the fixed slot keeps the neutral wash",
    dc[3]?.style === DARK.neutral,
    "slot 3 style " + dc[3]?.style,
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

console.log("");
console.log(passed + "/" + (passed + failed) + " checks passed");
if (failed > 0) process.exit(1);