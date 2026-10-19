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
function count(name) {
  ops[name] = (ops[name] || 0) + 1;
}
const ctxStub = {
  setTransform: () => count("setTransform"),
  clearRect: () => count("clearRect"),
  beginPath: () => count("beginPath"),
  stroke: () => count("stroke"),
  fill: () => count("fill"),
  moveTo: () => count("moveTo"),
  lineTo: () => count("lineTo"),
  arc: () => count("arc"),
};
ctxStub.__defineSetter__("lineWidth", () => {});
ctxStub.__defineSetter__("strokeStyle", () => {});
ctxStub.__defineSetter__("fillStyle", () => {});

const CSS = 500; // typical phone panel CSS px
const el = {
  width: 0,
  height: 0,
  getBoundingClientRect: () => ({ width: CSS, height: CSS, left: 0, top: 0 }),
  getContext: () => ctxStub,
};
globalThis.document = { getElementById: () => el };
globalThis.window = {
  devicePixelRatio: 3,
  addEventListener: () => {},
  localStorage: { getItem: () => null, setItem: () => {} },
};
let raf_cb = null;
globalThis.requestAnimationFrame = (cb) => {
  raf_cb = cb;
};

// ---- helpers ---------------------------------------------------------------
function make_terms(n) {
  const out = [];
  for (let i = 1; i <= n; i++) {
    out.push([i % 2 === 0 ? -i / 2 : (i + 1) / 2, 9 / i, i * 0.13]);
  }
  return out;
}
const reset = () => {
  for (const k of Object.keys(ops)) delete ops[k];
};
const total = () => Object.values(ops).reduce((a, b) => a + b, 0);

function drive(frames, start_ms = 0) {
  let now = start_ms;
  for (let i = 0; i < frames; i++) {
    now += 1000 / 60;
    raf_cb(now);
  }
}
const ms = (fn) => {
  const t0 = performance.now();
  fn();
  return performance.now() - t0;
};

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
ffi.canvas_sync(terms64, false, true);
reset();
let t_js = ms(() => drive(600));
console.log(
  `\nplaying 60fps × 600 frames  terms=64  ` +
    `ops/frame=${(total() / 600).toFixed(1)}  ` +
    `JS-side ${(t_js / 600 * 1000).toFixed(0)} μs/frame (math only; raster cost is browser-side)`,
);
const playing_ops = { ...ops };

// ---- 3. per-frame ops while PAUSED (the idle-burn check) -------------------
ffi.canvas_sync(terms64, false, false);
reset();
drive(600);
console.log(
  `paused 60fps × 600 frames  terms=64  ` +
    `ops/frame=${(total() / 600).toFixed(1)}  ← expected 0 if loop idled`,
);

// ---- 4. per-frame ops in FINAL mode ---------------------------------------
ffi.canvas_sync(terms64, true, true);
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
console.log(
  `\nper-frame stroke-call breakdown (playing, terms=64): ` +
    Object.entries(playing_ops)
      .filter(([k]) => k !== "setTransform")
      .map(([k, v]) => `${k}=${(v / 600).toFixed(0)}`)
      .join("  "),
);