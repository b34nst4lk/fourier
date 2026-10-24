// App-level smoke for the single-file dist artifact: loads dist/index.html
// into jsdom, evals the EXACT shipped bundle (jsdom can't run type="module"
// scripts, but the esbuild bundle is self-contained with no import/export
// syntax, so it evaluates identically as a classic script), and drives the
// real Lustre runtime end to end — the FINAL v2 interface: ONE puzzle (the
// quaver), no routing: the app boots straight into the board.
//
// Determinism: window.requestAnimationFrame is replaced with a manual queue
// (drained by tick()); canvas 2D contexts are replaced with op-counting
// stubs (element identity + op counts are the assertions; pixels are not).
// Ground truth for every displayed Match % comes from the compiled pure core
// (build/dev/.../puzzle.mjs + shapes.mjs) — the same code the app runs.
//
// Deps: jsdom resolvable via require (e.g. NODE_PATH=/tmp/jsdomcheck/node_modules).
// Run: node scripts/artifact_smoke.mjs

import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { toList } from "../build/dev/javascript/prelude.mjs";
import * as shapes from "../build/dev/javascript/fourier_toy/fourier_toy/shapes.mjs";
import * as puzzle from "../build/dev/javascript/fourier_toy/fourier_toy/puzzle.mjs";

const require = createRequire(import.meta.url);
let JSDOM;
try {
  ({ JSDOM } = require("jsdom"));
} catch {
  ({ JSDOM } = createRequire("/tmp/jsdomcheck/package.json")("jsdom"));
}

// ---- artifact ---------------------------------------------------------------
const html = readFileSync(new URL("../dist/index.html", import.meta.url), "utf8");
const m = html.match(/<script type="module">([\s\S]*?)<\/script>/);
if (!m) throw new Error("artifact: module script not found");
const bundle = m[1];
if (/\bimport\s|\bexport\s/.test(bundle)) {
  throw new Error("artifact: bundle carries ESM syntax — cannot eval as classic script");
}

// ---- stubs installed before the bundle runs ---------------------------------
let raf_q = [];
let raf_handle = 0;
let NOW = 1000.0;

function make_ctx() {
  const ops = { arc: 0, moveTo: 0, lineTo: 0, stroke: 0, nan: 0 };
  return {
    ops,
    setLineDash: () => {},
    setTransform: () => {},
    clearRect: () => {},
    beginPath: () => {},
    closePath: () => {},
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
    moveTo: (x, y) => {
      ops.moveTo++;
      if (!Number.isFinite(x) || !Number.isFinite(y)) ops.nan++;
    },
    lineTo: (x, y) => {
      ops.lineTo++;
      if (!Number.isFinite(x) || !Number.isFinite(y)) ops.nan++;
    },
    arc: (x, y, _r) => {
      ops.arc++;
      if (!Number.isFinite(x) || !Number.isFinite(y)) ops.nan++;
    },
    stroke: () => {
      ops.stroke++;
    },
  };
}

function boot_dom({ stored = null, systemDark = false } = {}) {
  raf_q = [];
  NOW = 1000.0;
  const dom = new JSDOM(html, {
    url: "https://toy.test/", // no hash — the app boots straight into the board
    runScripts: "dangerously",
    pretendToBeVisual: false,
    beforeParse(window) {
      window.devicePixelRatio = 2;
      window.requestAnimationFrame = (cb) => {
        raf_handle++;
        raf_q.push(cb);
        return raf_handle;
      };
      window.cancelAnimationFrame = () => {};
      // jsdom's matchMedia is inert — the boot reads the system preference
      // at init, so the stub must exist before the bundle runs
      window.matchMedia = (q) => ({
        matches: systemDark && /prefers-color-scheme:\s*dark/.test(q),
        addEventListener() {},
        removeEventListener() {},
      });
      // seed the stored theme choice (sibling's f-sketch-theme convention)
      if (stored) {
        try {
          window.localStorage.setItem("f-toy-theme", stored);
        } catch (e) {}
      }
      // ONE stable recording ctx per canvas element
      window.HTMLCanvasElement.prototype.getContext = function () {
        if (!this.__ctx) this.__ctx = make_ctx();
        return this.__ctx;
      };
      // jsdom has no layout engine (rects are all zeros): give the board its
      // real CSS size so fit()/sub-pixel skips behave as in a browser
      window.HTMLCanvasElement.prototype.getBoundingClientRect = () => ({
        width: 300,
        height: 300,
        left: 0,
        top: 0,
      });
    },
  });
  dom.window.eval(bundle); // lustre.start: init effects run, then the first render
  return dom;
}

function tick(ms = 34, n = 1) {
  for (let i = 0; i < n; i++) {
    NOW += ms;
    const q = raf_q;
    raf_q = [];
    for (const cb of q) cb(NOW);
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- ground truth (the compiled pure core — same code the app runs) --------
const setup = puzzle.quaver_setup();
const shape = puzzle.shape_of(setup.shape);
const initial_state = () => puzzle.initial(shape, setup.patches);
function step_slot(state, slot, dir) {
  const kinds = Array.from(setup.dials);
  // mirror update(): index-wise step, rebuilt as a real Gleam cons list
  return toList(
    Array.from(state, (s, i) =>
      i === slot ? puzzle.step(kinds[i], s, dir, shape.dial_max_r) : s,
    ),
  );
}
const match_of = (state) => shapes.match_pct(shape, state);

// ---- assertion harness -------------------------------------------------------
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
const text = (el) => (el ? el.textContent.trim() : null);

// ---- helpers over the live DOM ----------------------------------------------
function board_canvas(dom) {
  return dom.window.document.getElementById("toy-board");
}
function canvas_ops(dom) {
  const el = board_canvas(dom);
  return el && el.__ctx ? el.__ctx.ops : null;
}
function score_val(dom) {
  const el = dom.window.document.querySelector(".score b");
  return el ? text(el) : null;
}
function counter(dom) {
  const el = dom.window.document.querySelector(".score .mv");
  return el ? el.textContent.replace(/\s+/g, " ").trim() : null;
}
function counter_n(d) {
  return parseInt((counter(d) || "").replace(/[^0-9]/g, ""), 10);
}
function rows(dom) {
  return [...dom.window.document.querySelectorAll(".rows .row")];
}
// rendered rows skip fixed slots — map slot → rendered row
const rendered_slots = Array.from(setup.dials)
  .map((k, i) => (k.constructor.name !== "DialFixed" ? i : null))
  .filter((i) => i !== null);
function row_button(dom, slot, dir) {
  const r = rows(dom)[rendered_slots.indexOf(slot)];
  if (!r) return null;
  const btns = r.querySelectorAll("button.btn");
  return dir < 0 ? btns[0] : btns[1];
}
function row_val(dom, slot) {
  return text(rows(dom)[rendered_slots.indexOf(slot)].querySelector(".val"));
}

// ==== S0 · shipped CSS contract =================================================
console.log("S0 · artifact CSS — controls opt out of double-tap zoom");
{
  // jsdom cannot synthesize touch gestures; the shipped-CSS rule is the
  // behavior contract for "rapid stepper taps must not zoom" (pinch stays)
  const btnRule = html.match(/button \{[^}]*\}/);
  check(
    "steppers carry touch-action: manipulation (no double-tap zoom; pinch kept)",
    btnRule !== null && /touch-action:\s*manipulation/.test(btnRule[0]),
    "button rule: " + (btnRule ? btnRule[0].slice(0, 80) + "…" : "missing"),
  );
  check(
    "steppers opt out of text selection (long-press = hold-repeat, not loupe)",
    btnRule !== null &&
      /-webkit-user-select:\s*none/.test(btnRule[0]) &&
      /(^|[^-])user-select:\s*none/.test(btnRule[0]) &&
      /-webkit-touch-callout:\s*none/.test(btnRule[0]),
    "button rule: " + (btnRule ? btnRule[0] : "missing"),
  );
  check(
    "viewport stays user-scalable (pinch-zoom accessibility preserved)",
    !/user-scalable\s*=\s*no/i.test(html) && !/maximum-scale\s*=\s*1\b/i.test(html),
    "viewport meta limits zoom",
  );
  const valRule = html.match(/\.val \{[^}]*\}/);
  check(
    "dial readouts are plain text (no box)",
    valRule !== null && !/border/.test(valRule[0]) && !/background/.test(valRule[0]),
    "val rule: " + (valRule ? valRule[0].replace(/\s+/g, " ") : "missing"),
  );
}

// ==== S1 · boot straight into the quaver board ================================
console.log("S1 · cold load — boots straight into the quaver board, canvas painted");
const dom = boot_dom();
let state = initial_state();
tick(); // boot retry binds the canvas (init effects ran pre-render), frame queued
tick(34, 5); // draw frames
{
  const ops = canvas_ops(dom);
  check("canvas booted and painted", ops && ops.arc >= 5, "arcs " + (ops && ops.arc));
  check("no NaN coordinates", ops && ops.nan === 0, "nan " + (ops && ops.nan));
  check(
    "backing store sized (600 = 300css × dpr2)",
    board_canvas(dom).width === 600,
    String(board_canvas(dom).width),
  );
  const expect = puzzle.fmt1(match_of(state));
  check(
    "score shows the core-computed initial match",
    score_val(dom) === expect + "%",
    "dom " + score_val(dom) + " vs core " + expect + "%",
  );
  check("title is the single puzzle (quaver)", text(dom.window.document.querySelector("h2.pt")) === "quaver", text(dom.window.document.querySelector("h2.pt")));
  check("counter starts at zero (· 0 changes)", counter(dom) === "· 0 changes", JSON.stringify(counter(dom)));
  check("no routing chrome: no home cards, no back link", dom.window.document.querySelector("a.card") === null && dom.window.document.querySelector("a.back") === null);
  check("fixed slot 4 hidden (3 rows)", rows(dom).length === 3, "rows " + rows(dom).length);
  {
    // term 1 is the phase dial: its small print must lock r and k — not φ
    const s0 = Array.from(shape.dial)[0];
    const expectedSub =
      "locked: r " +
      puzzle.slot_value(Array.from(setup.dials)[1], s0, shape.dial_max_r) +
      " · k " +
      puzzle.fmt_k(s0.k);
    const sub1 = text(rows(dom)[0].querySelector(".sub"));
    check(
      "term 1's small print locks r and k (not φ — φ is the dial)",
      sub1 === expectedSub && !sub1.includes("φ"),
      sub1 + " vs " + expectedSub,
    );
  }
  const themeBtn = dom.window.document.querySelector("button.theme");
  const resetBtn = dom.window.document.querySelector("button.reset");
  check(
    "bar: unboxed score (b), icon chips — reset (↺, aria) + theme",
    dom.window.document.querySelector(".score b") !== null &&
      themeBtn.getAttribute("aria-label") === "dark mode" &&
      themeBtn.querySelector("svg.icon") !== null &&
      resetBtn !== null &&
      resetBtn.getAttribute("aria-label") === "reset to start" &&
      resetBtn.querySelector("svg.icon") !== null,
    "reset: " + (resetBtn ? resetBtn.getAttribute("aria-label") : "missing") +
      ", theme aria: " + themeBtn.getAttribute("aria-label"),
  );
}

// ==== S2 · dials: wrap, ground-truth steps, floor disable =====================
console.log("S2 · dial behavior — wrap, ground-truth steps, floor disable");
{
  // phase wrap: 355° + 5° → 0° (mod 360)
  row_button(dom, 0, 1).click();
  state = step_slot(state, 0, 1);
  tick();
  check("phase wraps past 360 (0°)", row_val(dom, 0) === "0°", row_val(dom, 0));
  check("one change counts (· 1 change, singular)", counter(dom) === "· 1 change", JSON.stringify(counter(dom)));
  check(
    "score tracks the stepped state",
    score_val(dom) === puzzle.fmt1(match_of(state)) + "%",
    "dom " + score_val(dom) + " vs core " + puzzle.fmt1(match_of(state)) + "%",
  );
  // radius floor: step slot 1 down to 0%
  // BEFORE any solve, reset starts a fresh attempt: the counter zeroes
  dom.window.document.querySelector("button.reset").click();
  state = initial_state();
  tick();
  check(
    "reset before any solve zeroes the counter",
    counter(dom) === "· 0 changes",
    JSON.stringify(counter(dom)),
  );
  check(
    "reset restores the phase dial (355°)",
    row_val(dom, 0) === "355°",
    row_val(dom, 0),
  );
  // redo the wrap so the counter arithmetic below stays exact
  row_button(dom, 0, 1).click();
  state = step_slot(state, 0, 1);
  tick();
  check(
    "counting resumes after the fresh reset (· 1 change)",
    counter(dom) === "· 1 change",
    JSON.stringify(counter(dom)),
  );
  // radius floor: step slot 1 down to 0% — the minus button must disable
  let clicks = 0;
  let btn = row_button(dom, 1, -1);
  while (!btn.disabled && clicks < 200) {
    btn.click();
    state = step_slot(state, 1, -1);
    clicks++;
    tick();
    btn = row_button(dom, 1, -1);
  }
  check(
    "radius floors at 0% and disables minus",
    row_val(dom, 1) === "0%" && btn.disabled,
    row_val(dom, 1) + " disabled=" + btn.disabled,
  );
  check(
    "counter tracks every step (1 + " + clicks + " = " + (clicks + 1) + " changes)",
    counter(dom) === "· " + (clicks + 1) + " changes",
    JSON.stringify(counter(dom)),
  );
}

// ==== S3 · hold-to-repeat on the steppers ======================================
console.log("S3 · hold-to-repeat — auto-steps while held, tap steps once");
{
  const fire = (name, el) =>
    el.dispatchEvent(new dom.window.Event(name, { bubbles: true }));
  const c0 = counter_n(dom);

  const v0 = parseInt(row_val(dom, 0), 10);
  const btn = row_button(dom, 0, -1);
  fire("pointerdown", btn);
  await sleep(700);
  fire("pointerup", btn);
  tick(); // flush the RAF-pending renders the repeats scheduled
  const v1 = parseInt(row_val(dom, 0), 10);
  // phase wraps mod 360 — the hold presses MINUS, so v1 ≡ v0 − 5n (mod 360)
  const n = ((v0 - v1 + 360) % 360) / 5;
  check(
    "hold auto-repeats the stepper (≥ 2 steps in 700ms)",
    n >= 2,
    v0 + "° → " + v1 + "° (n=" + n + ")",
  );
  for (let i = 0; i < n; i++) state = step_slot(state, 0, -1);
  check(
    "score matches the core after n repeat steps",
    score_val(dom) === puzzle.fmt1(match_of(state)) + "%",
    "dom " + score_val(dom) + " vs core " + puzzle.fmt1(match_of(state)) + "%",
  );
  check(
    "each repeat tick counts as a change",
    counter_n(dom) === c0 + n,
    c0 + " → " + counter_n(dom),
  );

  // the natural release-click after a repeated hold must be swallowed
  fire("click", btn);
  tick();
  check(
    "release click after a hold is swallowed (no double-step)",
    parseInt(row_val(dom, 0), 10) === v1,
    row_val(dom, 0) + " vs " + v1 + "°",
  );
  // a QUICK TAP (down+up inside the repeat threshold) steps exactly once
  fire("pointerdown", btn);
  fire("pointerup", btn);
  fire("click", btn);
  tick();
  state = step_slot(state, 0, -1);
  check(
    "quick tap steps exactly once",
    parseInt(row_val(dom, 0), 10) === ((v1 - 5 + 360) % 360) &&
      score_val(dom) === puzzle.fmt1(match_of(state)) + "%",
    row_val(dom, 0) + " vs " + ((v1 - 5 + 360) % 360) + "°, score " + score_val(dom),
  );
  check(
    "the tap's single step counts too",
    counter_n(dom) === c0 + n + 1,
    c0 + " + " + n + " + 1 vs " + counter_n(dom),
  );
}

// ==== S4 · dial-home solve path — from wherever the dials now stand ============
console.log("S4 · dial-home solve path — every dialable at (or nearest to) truth ⇒ solved");
let moves_at_solve = null;
{
  const truth = Array.from(shape.dial);
  const t0 = truth[0];
  const t1 = truth[1];
  const t2 = truth[2];
  const cur = Array.from(state);
  // phase: shortest direction around the dial, from the CURRENT phase
  const up = ((t0.phase_deg - cur[0].phase_deg + 360) % 360) / 5;
  const down = ((cur[0].phase_deg - t0.phase_deg + 360) % 360) / 5;
  const pdir = up <= down ? 1 : -1;
  for (let i = 0; i < Math.min(up, down); i++) {
    row_button(dom, 0, pdir).click();
    state = step_slot(state, 0, pdir);
    tick();
  }
  // radius: nearest reachable step to truth (unit = 2% of max)
  const unit = 0.02 * shape.dial_max_r;
  const r_delta = t1.r - cur[1].r;
  const rdir = r_delta >= 0 ? 1 : -1;
  for (let i = 0; i < Math.round(Math.abs(r_delta) / unit); i++) {
    row_button(dom, 1, rdir).click();
    state = step_slot(state, 1, rdir);
    tick();
  }
  // k: straight to truth
  const kdir = t2.k >= cur[2].k ? 1 : -1;
  for (let i = 0; i < Math.abs(t2.k - cur[2].k); i++) {
    row_button(dom, 2, kdir).click();
    state = step_slot(state, 2, kdir);
    tick();
  }
  tick(34, 3);
  check(
    "score matches the core at the stepped state",
    score_val(dom) === puzzle.fmt1(match_of(state)) + "%",
    "dom " + score_val(dom) + " vs core " + puzzle.fmt1(match_of(state)) + "%",
  );
  check(
    "solved badge appears at ≥ 95%",
    dom.window.document.querySelector(".score.solved") !== null,
    "score " + score_val(dom),
  );

  // the counter freezes at the FIRST solve: further steps stop counting,
  // and it stays frozen even after dialing back into unsolved territory
  moves_at_solve = counter_n(dom);
  row_button(dom, 0, 1).click(); // phase +5° past truth
  state = step_slot(state, 0, 1);
  tick(34, 2);
  check(
    "counter frozen at the first solve (extra step doesn't count)",
    counter_n(dom) === moves_at_solve,
    moves_at_solve + " → " + counter_n(dom),
  );
  row_button(dom, 2, -1).click(); // k off truth — definitely unsolved now
  state = step_slot(state, 2, -1);
  tick(34, 2);
  check(
    "counter stays frozen after dialing away",
    counter_n(dom) === moves_at_solve,
    moves_at_solve + " → " + counter_n(dom),
  );
  check(
    "badge drops when unsolved again",
    !dom.window.document.querySelector(".score.solved"),
  );
}

// ==== S5 · reset — dials back to start, the solved record survives ==========
console.log("S5 · reset — dials to start; the number you solved in is the number you keep");
{
  dom.window.document.querySelector("button.reset").click();
  state = initial_state();
  tick(34, 2);
  const expect = puzzle.fmt1(match_of(state));
  check(
    "reset restores the initial match",
    score_val(dom) === expect + "%",
    "dom " + score_val(dom) + " vs core " + expect + "%",
  );
  check(
    "badge gone after reset (unsolved again)",
    !dom.window.document.querySelector(".score.solved"),
  );
  check(
    "the solved record survives reset (counter unchanged)",
    counter_n(dom) === moves_at_solve,
    moves_at_solve + " vs " + counter_n(dom),
  );
  // play after a solved reset does NOT re-count — the record is final
  row_button(dom, 2, 1).click(); // k −5 → −4
  state = step_slot(state, 2, 1);
  tick();
  check(
    "steps after a solved reset don't count (record is final)",
    counter_n(dom) === moves_at_solve,
    moves_at_solve + " vs " + counter_n(dom),
  );
  check(
    "but the dial still steps (k reads −4)",
    row_val(dom, 2) === "k " + puzzle.fmt_k(-4),
    row_val(dom, 2),
  );
}

// ==== S6 · theme toggle ========================================================
console.log("S6 · theme toggle mirrors onto the body");
{
  const themeBtn = () => dom.window.document.querySelector("button.theme");
  themeBtn().click();
  tick();
  check("body flips to dark", dom.window.document.body.getAttribute("data-theme") === "dark");
  check(
    "choice saved to localStorage (f-toy-theme: dark)",
    dom.window.localStorage.getItem("f-toy-theme") === "dark",
    JSON.stringify(dom.window.localStorage.getItem("f-toy-theme")),
  );
  check(
    "chip flips to the sun (aria-label light mode, icon swaps)",
    themeBtn().getAttribute("aria-label") === "light mode" &&
      themeBtn().querySelectorAll("svg.icon line").length > 0,
  );
  themeBtn().click();
  tick();
  check("body flips back to light", dom.window.document.body.getAttribute("data-theme") === "light");
  check(
    "choice updated in localStorage (f-toy-theme: light)",
    dom.window.localStorage.getItem("f-toy-theme") === "light",
    JSON.stringify(dom.window.localStorage.getItem("f-toy-theme")),
  );
}

// ==== S7 · theme persistence ==================================================
console.log("S7 · theme persistence — stored choice beats system preference");
{
  const chipOf = (d) => d.window.document.querySelector("button.theme");
  const bodyTheme = (d) => d.window.document.body.getAttribute("data-theme");

  const storedDark = boot_dom({ stored: "dark", systemDark: false });
  tick();
  check(
    "stored dark boots dark (stored beats system light)",
    bodyTheme(storedDark) === "dark" && chipOf(storedDark).getAttribute("aria-label") === "light mode",
    "body " + bodyTheme(storedDark),
  );

  const storedLightSysDark = boot_dom({ stored: "light", systemDark: true });
  tick();
  check(
    "stored light boots light (stored beats system dark)",
    bodyTheme(storedLightSysDark) === "light" && chipOf(storedLightSysDark).getAttribute("aria-label") === "dark mode",
    "body " + bodyTheme(storedLightSysDark),
  );

  const noStoredSysDark = boot_dom({ systemDark: true });
  tick();
  check(
    "no stored choice: system preference applies (dark)",
    bodyTheme(noStoredSysDark) === "dark",
    "body " + bodyTheme(noStoredSysDark),
  );
}

console.log("");
console.log(passed + "/" + (passed + failed) + " checks passed");
if (failed > 0) process.exit(1);