// Resource/compute audit for the panel-2 canvas RAF loop.
// Drives the REAL FFI module against a stub canvas that counts draw ops,
// so per-frame cost is measured as code actually behaves (including when
// paused / in final mode). Rasterization itself can't run in Node — the
// GPU-side cost is reported analytically from measured op counts + DPR.
//
// Run: node scripts/bench_render.mjs

import * as ffi from "../src/fourier_sketch_ffi.mjs";

// ---- stub DOM --------------------------------------------------------------
const ops = {};
const calls = []; // recorded draw-call coords, reset alongside ops
function count(name) {
  ops[name] = (ops[name] || 0) + 1;
}
const ctxStub = {
  setTransform: () => count("setTransform"),
  clearRect: () => count("clearRect"),
  beginPath: () => count("beginPath"),
  stroke: () => count("stroke"),
  fill: () => count("fill"),
  moveTo: (x, y) => {
    count("moveTo");
    calls.push(["moveTo", Math.round(x * 100) / 100, Math.round(y * 100) / 100]);
  },
  lineTo: (x, y) => {
    count("lineTo");
    calls.push(["lineTo", Math.round(x * 100) / 100, Math.round(y * 100) / 100]);
  },
  arc: (x, y, r) => {
    count("arc");
    calls.push([
      "arc",
      Math.round(x * 100) / 100,
      Math.round(y * 100) / 100,
      Math.round(r * 100) / 100,
    ]);
  },
};
ctxStub.__defineSetter__("lineWidth", () => {});
ctxStub.__defineSetter__("strokeStyle", () => {});
ctxStub.__defineSetter__("fillStyle", () => {});

const CSS = 500; // typical phone panel CSS px
const mkEl = () => ({
  width: 0,
  height: 0,
  getBoundingClientRect: () => ({ width: CSS, height: CSS, left: 0, top: 0 }),
  getContext: () => ctxStub,
});
const el = mkEl();
let els = [el]; // element generations — a remount hands boot a fresh element
let gen = 0;
let canvas_in_dom = true; // simulates Lustre mounting/unmounting the canvas
globalThis.document = {
  body: { getAttribute: () => null }, // palette probe: light palette
  getElementById: () => (canvas_in_dom ? els[gen] : null),
};
globalThis.window = {
  devicePixelRatio: 3,
  addEventListener: () => {},
  localStorage: { getItem: () => null, setItem: () => {} },
};
// browser-faithful rAF: returns a unique handle, multiple callbacks may be
// pending (an app frame and a boot retry can coexist in one tick)
let raf_q = [];
let raf_handle = 0;
globalThis.requestAnimationFrame = (cb) => {
  raf_handle++;
  raf_q.push(cb);
  return raf_handle;
};
globalThis.cancelAnimationFrame = () => {};

// IntersectionObserver stub — captures the instance so the verify section can
// fire visibility transitions manually (harmless before the fix exists).
let io_instance = null;
globalThis.IntersectionObserver = class {
  constructor(cb) {
    this.cb = cb;
    io_instance = this;
  }
  observe() {}
  disconnect() {}
};

// ---- helpers ---------------------------------------------------------------
// A Gleam List on the JS target is iterable but NOT an array — no .length,
// no index access. All sync contracts feed this shape so the harness can
// never again pass on array-shaped data while the app ships list-shaped.
class GleamishList {
  constructor(rows) {
    this._rows = rows;
    Object.defineProperty(this, "length", { value: undefined });
  }
  [Symbol.iterator]() {
    return this._rows[Symbol.iterator]();
  }
}

function make_terms(n) {
  const out = [];
  for (let i = 1; i <= n; i++) {
    out.push([i % 2 === 0 ? -i / 2 : (i + 1) / 2, 9 / i, i * 0.13]);
  }
  return new GleamishList(out);
}
const reset = () => {
  for (const k of Object.keys(ops)) delete ops[k];
  calls.length = 0;
};
const total = () => Object.values(ops).reduce((a, b) => a + b, 0);

let sim_now = 0; // monotonic simulated clock — drive() must not regress it,
// the FFI's gates compare against real elapsed time
function drive(frames) {
  for (let i = 0; i < frames; i++) {
    sim_now += 1000 / 60;
    const q = raf_q;
    raf_q = []; // callbacks scheduled this tick run NEXT tick (browser-faithful)
    for (const cb of q) cb(sim_now);
  }
}
const ms = (fn) => {
  const t0 = performance.now();
  fn();
  return performance.now() - t0;
};

let failures = 0;
function verify(label, cond) {
  console.log(`${cond ? "PASS" : "FAIL"}  ${label}`);
  if (!cond) failures++;
}

// ---- 0a. boot-before-mount contract (fresh-load reproduction) -------------
// Lustre can run the canvas_sync effect BEFORE the view is attached (repro:
// the init effect found fourier-canvas null even with a restored sketch).
// The loop must self-start once the canvas appears — with no further
// canvas_sync/boot calls from the app.
canvas_in_dom = false;
ffi.canvas_boot("fourier-canvas"); // el null → boot must schedule a retry
ffi.canvas_sync(make_terms(64), true); // pump: ctx still null → no draw
canvas_in_dom = true; // element appears at patch time
reset();
drive(120);
verify(
  "boot-before-mount: loop self-starts once canvas mounts (≥10 draws)",
  (ops.clearRect || 0) >= 10,
);

// ---- 0. boot --------------------------------------------------------------
ffi.canvas_boot("fourier-canvas");
reset();

// ---- 1. sync cost = rebuild_cache (STEPS×terms×2 trig per sync) ------------
// warm-up first so both rows are measured JIT-hot
for (const n of [64, 256]) ms(() => ffi.canvas_sync(make_terms(n), false, true));
for (const label of [1, 2]) {
  for (const n of [64, 256]) {
    const terms = make_terms(n);
    reset();
    const t = ms(() => ffi.canvas_sync(terms, false, true));
    if (label === 2)
      console.log(
        `sync/rebuild_cache  terms=${String(n).padStart(3)}  ` +
          `${t.toFixed(2)} ms  (runs on EVERY model change, incl. pause toggles)`,
      );
  }
}

// ---- 2. per-frame ops while PLAYING ---------------------------------------
const terms64 = make_terms(64);
ffi.canvas_sync(terms64, true);
reset();
let t_js = ms(() => drive(600));
console.log(
  `\nplaying 60fps × 600 frames  terms=64  ` +
    `ops/frame=${(total() / 600).toFixed(1)}  ` +
    `JS-side ${(t_js / 600 * 1000).toFixed(0)} μs/frame (math only; raster cost is browser-side)`,
);
const playing_ops = { ...ops };

// ---- 3. per-frame ops while PAUSED (the idle-burn check) -------------------
ffi.canvas_sync(terms64, false);
reset();
drive(600);
console.log(
  `paused 60fps × 600 frames  terms=64  ` +
    `ops/frame=${(total() / 600).toFixed(1)}  ← expected 0 if loop idled`,
);

// ---- 4. per-frame ops in FINAL mode ---------------------------------------
ffi.canvas_sync(terms64, false);
reset();
drive(600);
console.log(
  `final  60fps × 600 frames  terms=64  ` +
    `ops/frame=${(total() / 600).toFixed(1)}  ← expected 0 if loop idled`,
);

// ---- 5. worst case per-frame ops (256 terms) ------------------------------
ffi.canvas_sync(make_terms(256), false, true);
reset();
drive(600);
console.log(
  `playing 60fps × 600 frames  terms=256  ops/frame=${(total() / 600).toFixed(1)}`,
);

// ---- 6. analytic fill-rate table (what Node cannot measure) ---------------
console.log(
  `\nfill-rate model: panel ${CSS}×${CSS} CSS px, draw ops/frame above;` +
    ` canvas backing store = CSS × devicePixelRatio`,
);
for (const dpr of [1, 2, 3]) {
  const side = CSS * dpr;
  const px = side * side;
  console.log(
    `  dpr=${dpr}  backing ${side | 0}×${side | 0} = ` +
      `${(px / 1e6).toFixed(2)} Mpx cleared+repainted per frame ` +
      `(full clearRect + full redraw, no dirty gating)`,
  );
}
// ---- 7. repeated calculations per frame -----------------------------------
// The FFI computes Math.cos/sin via global lookup at call time, so patching
// counts exactly what the shipping draw() recomputes each frame.
const real_cos = Math.cos,
  real_sin = Math.sin;
let cos_n = 0,
  sin_n = 0;
Math.cos = (x) => {
  cos_n++;
  return real_cos(x);
};
Math.sin = (x) => {
  sin_n++;
  return real_sin(x);
};

function trig_case(label, terms, final, playing) {
  ffi.canvas_sync(terms, playing); // sync costs one rebuild: not part of per-frame count
  cos_n = 0;
  sin_n = 0;
  drive(120);
  const per_frame = (cos_n + sin_n) / 120;
  console.log(
    `${label.padEnd(8)} terms=${String([...terms].length).padStart(3)}  ` +
      `cos/sin calls per frame=${per_frame.toFixed(1)}` +
      (playing || final ? "" : "  ← identical output every frame"),
  );
}
trig_case("playing", make_terms(64), false, true);
trig_case("playing", make_terms(256), false, true);
trig_case("paused", make_terms(64), false, false);
// the final frame ≡ the standing state (final is derived as ¬playing)
trig_case("final", make_terms(64), true, false);
Math.cos = real_cos;
Math.sin = real_sin;

// ---- 8. machine-verified behavior contracts (RED→GREEN gate) --------------

// trace cache must reflect the CURRENT terms, not one sync late (stale-rebuild
// regression): one term k=1, r=10, φ=0 ⇒ the trace's index-64 point sits at
// sketch ≈(0,10) → canvas (0,50) (square 500px panel: scale 5, ox/oy 0) — a
// coordinate no circle/link stroke can produce.
reset();
ffi.canvas_sync(new GleamishList([[1, 10, 0]]), true, true); // list-shaped
drive(4);
const tracePoint = calls.find(
  (c) =>
    c[0] === "lineTo" &&
    Math.abs(c[1] - 0) < 0.25 &&
    Math.abs(c[2] - 50) < 0.25,
);
verify(
  "trace cache built from CURRENT terms (trace hits (0,50))",
  Boolean(tracePoint),
);

// dpr capped at 2: 500 CSS px @ dpr 3 => 1000px backing store
verify(
  "dpr cap: backing store = 500×2 = 1000 (was 1500 at dpr=3)",
  el.width === 1000 && el.height === 1000,
);

// paused: exactly one repaint on sync, then the loop disengages
ffi.canvas_sync(terms64, false);
reset();
drive(600);
verify(`paused: 1 draw in 600 frames (was 600)`, ops.clearRect === 1);

// final frame: one repaint on sync, then idle
ffi.canvas_sync(terms64, false);
reset();
drive(600);
verify(`final: 1 draw in 600 frames (was 600)`, ops.clearRect === 1);

// playing: 30fps gate => ~half the draws of a 60fps budget
ffi.canvas_sync(terms64, true);
reset();
drive(600);
verify(
  "playing @30fps gate: ~300 draws in 600 frames (was 600)",
  ops.clearRect >= 250 && ops.clearRect <= 330,
);

// canvas off-screen: render loop fully disengaged
if (!io_instance) {
  verify("off-screen gating: IntersectionObserver wired", false);
} else {
  io_instance.cb([{ isIntersecting: false }]);
  reset();
  drive(600);
  verify("off-screen: 0 draws in 600 frames", (ops.clearRect || 0) === 0);
  io_instance.cb([{ isIntersecting: true }]);
  drive(600);
  verify(
    "back on-screen: playing loop resumes (~30fps)",
    ops.clearRect >= 30,
  );
}

// sync with unchanged terms skips the O(STEPS×terms) rebuild_cache
Math.cos = (x) => {
  cos_n++;
  return real_cos(x);
};
Math.sin = (x) => {
  sin_n++;
  return real_sin(x);
};
const t64 = make_terms(64);
ffi.canvas_sync(t64, false, true);
const rebuilt_once = cos_n + sin_n;
ffi.canvas_sync(t64, false, true); // identical terms
const rebuilt_twice = cos_n + sin_n - rebuilt_once;
Math.cos = real_cos;
Math.sin = real_sin;
verify(
  `sync w/ unchanged terms: rebuild skipped (0 trig, was ${rebuilt_twice})`,
  rebuilt_twice === 0,
);

// ---- remount contract (clear bug) -----------------------------------------
// clear unmounts the canvas (<3 dots ⇒ placeholder). The browser IO fires
// isIntersecting:false on the detached element. A new shape remounts a NEW
// canvas element; boot must rebind canvas/ctx, re-observe with the IO, and
// the loop must resume — with no help from beyond the normal sync flow.
canvas_in_dom = false; // clear → canvas unmounts
io_instance.cb([{ isIntersecting: false }]); // detach notification (browser behavior)
ffi.canvas_boot("fourier-canvas"); // the app's sync calls boot first (context: null)
ffi.canvas_sync(new GleamishList([]), false, true); // clear pushes empty targets
reset();
drive(60);
verify(
  "unmounted canvas: loop idles, 0 draws (was painting to detached canvas)",
  (ops.clearRect || 0) === 0,
);
canvas_in_dom = true; // new shape ⇒ ≥3 dots ⇒ canvas REMOUNTS fresh
gen = 1;
els.push(mkEl());
ffi.canvas_boot("fourier-canvas"); // boot+sync, as the app's sync does
ffi.canvas_sync(make_terms(64), true);
reset();
drive(120);
verify(
  "remount: loop resumes on the new canvas (≥10 draws)",
  (ops.clearRect || 0) >= 10,
);

console.log(failures === 0 ? "\nALL VERIFICATIONS PASS" : `\n${failures} FAILURES`);
process.exitCode = failures === 0 ? 0 : 1;