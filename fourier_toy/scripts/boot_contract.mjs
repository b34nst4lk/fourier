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
    segments: [], // one coordinate list per stroke — draw-order structure
  };
  let seg = []; // coords accumulated since the last stroke
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
      return 1;
    },
    set lineWidth(_) {},
    get strokeStyle() {
      return "";
    },
    set strokeStyle(_) {},
    get globalAlpha() {
      return 1;
    },
    set globalAlpha(_) {},
    setTransform: (a, b, c, d, e, f) => {
      ops.setTransform_args = [a, b, c, d, e, f];
    },
    clearRect: () => {
      ops.clearRect++;
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
      push(x, y);
      ops.pen = [x, y];
    },
    stroke: () => {
      ops.stroke++;
      ops.segments.push(seg);
      seg = [];
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

function setup_of(id) {
  const r = puzzle.find(id);
  const s = r && r[0]; // Ok's payload sits at index 0 (Error → undefined)
  if (!s || !s.patches || !s.dials) throw new Error("no setup " + id);
  return s;
}

// The exact pushes ffi.gleam makes for a Board page: canvas_shape(shape),
// then canvas_terms(state). The Gleam side pre-maps BOTH TermState lists to
// #(k, r, phase_deg) tuples (ffi.gleam `row`) — replicate that here.
function sync_board(setup) {
  const shape = puzzle.shape_of(setup.shape);
  const extras = Array.from(shape.extras, (t) => [t.k, t.r, t.phase_deg]);
  ffi.canvas_shape(shape.centroid, shape.target, extras);
  const state = puzzle.initial(shape, setup.patches);
  ffi.canvas_terms(Array.from(state, (s) => [s.k, s.r, s.phase_deg]));
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
  const setup = setup_of("p6"); // star: DialP, DialR, DialK, DialFixed
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
  const setup = setup_of("p6");
  const shape = puzzle.shape_of(setup.shape);
  const rows = step_state(shape, setup, puzzle.initial(shape, setup.patches), 0, -1); // phase −5°
  const before = registry.getContext().ops.arc;
  ffi.canvas_terms(rows.map((s) => [s.k, s.r, s.phase_deg]));
  for (let i = 0; i < 3; i++) tick(34);
  const after = registry.getContext().ops.arc;
  check("dial change repaints (arcs grew)", after > before, before + " → " + after);
  check("still no NaN", registry.getContext().ops.nan === 0);
}

console.log("S3 · board→board — element replaced between syncs rebinds on the next sync");
{
  const old_el = registry;
  const setup_flower = setup_of("p7");
  sync_board(setup_flower); // sync runs pre-render: old element still mounted
  registry = make_el(); // the render REPLACED the canvas element
  const new_el = registry;
  // the next sync (any dial press) must bind the new element
  const shape = puzzle.shape_of(setup_flower.shape);
  const rows = step_state(shape, setup_flower, puzzle.initial(shape, setup_flower.patches), 0, 1);
  ffi.canvas_terms(rows.map((s) => [s.k, s.r, s.phase_deg]));
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
  const setup = setup_of("p9"); // quaver
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
    const setup = setup_of("p6");
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
  const setup = setup_of("p9"); // quaver: 4 dial terms + 25 rotating extras
  const shape = puzzle.shape_of(setup.shape);
  const extras = Array.from(shape.extras, (t) => [t.k, t.r, t.phase_deg]);
  ffi.canvas_shape(shape.centroid, shape.target, extras);
  ffi.canvas_terms(Array.from(shape.dial, (s) => [s.k, s.r, s.phase_deg])); // TRUTH
  tick(); // bind + queue frame
  tick(34, 3); // draws at t = 0.00625 + k·0.00425
  const ops = registry.getContext().ops;
  check(
    "DPR transform applied (setTransform dpr·identity)",
    JSON.stringify(ops.setTransform_args) === "[2,0,0,2,0,0]",
    "got " + JSON.stringify(ops.setTransform_args),
  );
  // all geometry checks read the LAST draw only: 16 segments per draw
  // (target, circles, links, 12 comet chunks, pen)
  const segs = ops.segments;
  const d0 = segs.length - 16;
  const pen = ops.pen;
  const lastChunk = segs[d0 + 14]; // last comet chunk of the last draw
  const cometEnd = lastChunk[lastChunk.length - 1];
  const gap = Math.hypot(pen[0] - cometEnd[0], pen[1] - cometEnd[1]);
  check(
    "pen sits on the comet's leading edge (≤ 1.3px)",
    gap <= 1.3,
    gap.toFixed(2) + "px",
  );
  // at truth the current synthesis IS the target synthesis: the comet must
  // overlay the dashed target (both are the same 512-sample full-synthesis
  // curve — extras rotating, not a constant offset)
  const target = segs[d0];
  const comet = segs.slice(d0 + 3, d0 + 15).flat();
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
}

console.log("");
console.log(passed + "/" + (passed + failed) + " checks passed");
if (failed > 0) process.exit(1);