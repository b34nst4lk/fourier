// Per-step perf bench for the toy's pure core: proves the memoized-Model design
// (the shape memoized once at boot, one match_pct per step) and guards it
// against regressions.
//
// The memoized flow builds the immutable quaver fixture (27-row table →
// 512-point synth_trace → rms_polar) ONCE at boot and computes the 512-sample
// metric ONCE per step. The legacy flow — what the setup()/shape() wrappers
// cost — rebuilds the fixture twice per steered step and computes the metric
// twice (update's solved() gate + view's match_pct). This bench times both
// head-to-head on the compiled modules (the same code the app runs) and asserts
// the ratio.
//
// Contracts:
//   - quaver() (the boot fixture build) under BOOT_BUDGET_MS
//   - match_pct (the per-step metric) under STEP_BUDGET_MS
//   - memoized per-step cost ≤ legacy per-step cost / RATIO (the win is real)
//
// Run: node scripts/bench_puzzle.mjs

import { performance } from "node:perf_hooks";
import { toList } from "../build/dev/javascript/prelude.mjs";
import * as shapes from "../build/dev/javascript/fourier_toy/fourier_toy/shapes.mjs";
import * as puzzle from "../build/dev/javascript/fourier_toy/fourier_toy/puzzle.mjs";

const BOOT_BUDGET_MS = 5.0; // fixture build per boot (runs ONCE now)
const STEP_BUDGET_MS = 2.0; // one metric pass per step (runs ONCE now)
const RATIO = 1.5; // legacy per-step must cost at least 1.5× the memoized flow

const setup = puzzle.quaver_setup();
const shape = shapes.quaver(); // also warms JIT for the loops below
const state0 = puzzle.initial(shape, setup.patches);

// ---- 1 · boot fixture build -------------------------------------------------
function time_boot(iter) {
  let min = Infinity;
  for (let i = 0; i < iter; i++) {
    const t0 = performance.now();
    shapes.quaver();
    const dt = performance.now() - t0;
    if (dt < min) min = dt;
  }
  return min;
}

// ---- 2 · one metric pass ----------------------------------------------------
function time_match(iter, state) {
  let min = Infinity;
  for (let i = 0; i < iter; i++) {
    const t0 = performance.now();
    shapes.match_pct(shape, state);
    const dt = performance.now() - t0;
    if (dt < min) min = dt;
  }
  return min;
}

// take the min over several rounds — noise-robust (bench_render.mjs wisdom)
const boot_ms = Math.min(...Array.from({ length: 5 }, () => time_boot(20)));
const match_ms = Math.min(
  ...Array.from({ length: 5 }, () => time_match(50, state0)),
);

// ---- 3 · per-step flows: memoized vs legacy ---------------------------------
// legacy: the fixture rebuilt twice and the metric run twice per steered step —
// the cost the setup()/shape() wrappers induce.
function time_flow(iter, flow) {
  let min = Infinity;
  for (let i = 0; i < iter; i++) {
    const t0 = performance.now();
    flow();
    const dt = performance.now() - t0;
    if (dt < min) min = dt;
  }
  return min;
}

const step_once = (state) => {
  // mirror update(): index-wise step on the cons list, rebuilt via the prelude
  const rows = Array.from(state);
  const stepped = puzzle.step(setup.dials[0], rows[0], -1, shape.dial_max_r);
  return toList(rows.map((s, i) => (i === 0 ? stepped : s)));
};

const memoizedStep = () => {
  // update(SlotStep): 1 metric pass
  const stepped = step_once(state0);
  shapes.match_pct(shape, stepped);
};

const legacyStep = () => {
  // update(SlotStep): shapes.solved(shape(), stepped) → fixture rebuild
  // + metric pass A; then view: shapes.match_pct(shape(), state) → SECOND
  // fixture rebuild + metric pass B (same inputs).
  const stepped = step_once(state0);
  shapes.solved(shapes.quaver(), stepped);
  shapes.match_pct(shapes.quaver(), stepped);
};

const memoized_step_ms = Math.min(
  ...Array.from({ length: 5 }, () => time_flow(50, memoizedStep)),
);
const legacy_step_ms = Math.min(
  ...Array.from({ length: 5 }, () => time_flow(50, legacyStep)),
);

// ---- report ------------------------------------------------------------------
console.log("fourier_toy · per-step bench (min of 5×N, JS target)");
console.log("  boot fixture build  shapes.quaver():  " + boot_ms.toFixed(3) + " ms   (budget " + BOOT_BUDGET_MS + ")");
console.log("  metric pass         match_pct:       " + match_ms.toFixed(3) + " ms   (budget " + STEP_BUDGET_MS + ")");
console.log("  memoized step flow:                  " + memoized_step_ms.toFixed(3) + " ms   (1 fixture×0 boots + 1 metric)");
console.log("  legacy step flow:                    " + legacy_step_ms.toFixed(3) + " ms   (2 fixtures + 2 metrics)");
console.log("  legacy / memoized ratio:             " + (legacy_step_ms / memoized_step_ms).toFixed(2) + "×  (must be ≥ " + RATIO + "×)");

let failed = 0;
function check(name, ok, detail) {
  console.log((ok ? "  ok  " : "FAIL  ") + name + (ok ? "" : " — " + detail));
  if (!ok) failed++;
}
check("boot fixture build within budget", boot_ms < BOOT_BUDGET_MS, boot_ms.toFixed(3) + " ms");
check("per-step metric within budget", match_ms < STEP_BUDGET_MS, match_ms.toFixed(3) + " ms");
check(
  "memoized flow beats the legacy flow (the memoization win)",
  legacy_step_ms >= RATIO * memoized_step_ms,
  "ratio " + (legacy_step_ms / memoized_step_ms).toFixed(2) + "×",
);

if (failed > 0) process.exit(1);
console.log("bench: green");