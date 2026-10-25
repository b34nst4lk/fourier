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

// The network half of the daily puzzle (PLAN-daily-puzzles.md §1). jsdom has no
// fetch, so the smoke supplies one: `fetchMode` picks the answer to
// GET /api/puzzle/today ("none" is the default — the empty calendar every
// pre-daily scenario boots into), and every call is logged so the scenarios can
// count and read the POSTs. POSTs answer 200 unless `postFails`.
function install_fetch(window, { fetchMode = "none", fetchBody = null, postFails = false }) {
  const calls = [];
  window.__calls = calls;
  window.fetch = (url, init = {}) => {
    const method = (init.method || "GET").toUpperCase();
    calls.push({ url: String(url), method, body: init.body === undefined ? null : init.body });
    if (method !== "GET") {
      if (postFails) return Promise.reject(new Error("offline"));
      return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve("{}") });
    }
    if (fetchMode === "reject") return Promise.reject(new Error("offline"));
    if (fetchMode === "http500") {
      return Promise.resolve({ ok: false, status: 500, text: () => Promise.resolve("") });
    }
    const body = fetchMode === "ok" ? fetchBody : JSON.stringify({ status: "none", fallback: true });
    return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve(body) });
  };
}

function boot_dom({
  stored = null,
  systemDark = false,
  seed = null,
  fetchMode = "none",
  fetchBody = null,
  postFails = false,
} = {}) {
  raf_q = [];
  NOW = 1000.0;
  const dom = new JSDOM(html, {
    url: "https://toy.test/", // no hash — the app boots straight into the board
    runScripts: "dangerously",
    pretendToBeVisual: false,
    beforeParse(window) {
      install_fetch(window, { fetchMode, fetchBody, postFails });
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
      // seed a stored attempt / identity (the daily puzzle's keys)
      if (seed) {
        for (const [key, value] of Object.entries(seed)) {
          try {
            window.localStorage.setItem(key, value);
          } catch (e) {}
        }
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


// ==== S8 · the daily puzzle: fetch → board → store → telemetry ==============
// PLAN-daily-puzzles.md §1. The served document here is built from the toy's
// own quaver numbers (dial truth, extras, target, centroid) with a DIFFERENT
// name and start, so the board proves it took the fetched puzzle over: the
// title changes, the date appears, and the dials sit where the served patches
// put them. The wiring under test is the toy's, not the derivation's — the
// derivation has its own gold tests in toy_admin.
console.log("S8 · daily puzzle — fetch, resume, solve POST, abandon, new day");

const DAILY_NAME = "the quaver, published";
const DAILY_DATE = "2026-10-26";
const OLD_DATE = "2026-10-25";

// patch constructors, as the app's core would build them ([phase, radius%, k])
const patches_of = (list) =>
  toList([
    puzzle.Patch$PhaseDeg(list[0]),
    puzzle.Patch$RPct(list[1]),
    puzzle.Patch$KSet(list[2]),
    puzzle.Patch$Keep$const,
  ]);
const daily_start_patches = patches_of([90.0, 50.0, 2]);

const daily_doc = () => ({
  status: "ok",
  puzzle: {
    name: DAILY_NAME,
    showDate: DAILY_DATE,
    dots: [
      [10, 50],
      [90, 50],
    ],
    centroid: [shape.centroid[0], shape.centroid[1]],
    dials: ["phase", "radius", "k", "fixed"],
    dial: Array.from(shape.dial, (t) => ({ k: t.k, radius: t.r, phase: t.phase_deg })),
    extras: Array.from(shape.extras, (t) => ({ k: t.k, radius: t.r, phase: t.phase_deg })),
    patches: [
      { kind: "phase", deg: 90.0 },
      { kind: "radius", pct: 50.0 },
      { kind: "k", k: 2 },
      { kind: "keep" },
    ],
    target: Array.from(shape.target, (p) => [p[0], p[1]]),
  },
});
const daily_json = () => JSON.stringify(daily_doc());

// the app derives these client-side (shapes.from_parts) — the ground truth for
// the daily board's score is the same derivation
const daily_shape = shapes.from_parts(
  DAILY_NAME,
  shape.centroid,
  shape.dial,
  shape.extras,
  shape.target,
);
const daily_initial = () => puzzle.initial(daily_shape, daily_start_patches);

// the walk S4 performs through the UI, computed on the core: phase the
// shortest way round, radius to its nearest step, then k — [[slot, dir], ...]
function walk_moves(shape_, kinds, start) {
  const cur = Array.from(start);
  const truth = Array.from(shape_.dial);
  const moves = [];
  const push = (slot, dir) => {
    cur[slot] = puzzle.step(kinds[slot], cur[slot], dir, shape_.dial_max_r);
    moves.push([slot, dir]);
  };
  const up = ((truth[0].phase_deg - cur[0].phase_deg + 360) % 360) / 5;
  const down = ((cur[0].phase_deg - truth[0].phase_deg + 360) % 360) / 5;
  const pdir = up <= down ? 1 : -1;
  for (let i = 0; i < Math.min(up, down); i++) push(0, pdir);
  const unit = 0.02 * shape_.dial_max_r;
  const rdir = truth[1].r - cur[1].r >= 0 ? 1 : -1;
  const rsteps = Math.round(Math.abs(truth[1].r - cur[1].r) / unit); // snapshot too
  for (let i = 0; i < rsteps; i++) push(1, rdir);
  const kdir = truth[2].k >= cur[2].k ? 1 : -1;
  const ksteps = Math.abs(truth[2].k - cur[2].k); // snapshot: push() mutates cur
  for (let i = 0; i < ksteps; i++) push(2, kdir);
  return { state: cur, moves };
}
const DAILY_KINDS = [
  puzzle.DialKind$DialP$const,
  puzzle.DialKind$DialR$const,
  puzzle.DialKind$DialK$const,
  puzzle.DialKind$DialFixed$const,
];
const daily_walk = walk_moves(daily_shape, DAILY_KINDS, daily_initial());

// the stored attempt, in the app's own schema (`j-att`, see attempt.gleam)
const attempt_json = (fields) =>
  JSON.stringify({
    v: 1,
    date: fields.date,
    state: (fields.state || Array.from(daily_initial())).map((s) => ({
      k: s.k,
      r: s.r,
      phase: s.phase_deg,
    })),
    moves: fields.moves || [],
    count: fields.count,
    solved: !!fields.solved,
    reported: !!fields.reported,
  });

const posts = (dom) => dom.window.__calls.filter((c) => c.method === "POST");
const gets = (dom) => dom.window.__calls.filter((c) => c.method === "GET");
const stored_attempt = (dom) => {
  const raw = dom.window.localStorage.getItem("j-att");
  return raw === null ? null : JSON.parse(raw);
};
const h2_text = (dom) => text(dom.window.document.querySelector("h2.pt"));
const when_text = (dom) => text(dom.window.document.querySelector("h2.pt .when"));
const uuid_now = (dom) => dom.window.localStorage.getItem("j-uid");

// ==== S8a · nothing published — the quaver, and NO telemetry ================
{
  const dom = boot_dom(); // default fetchMode: {"status":"none"}
  // the deterministic first paint, before the answer has settled
  check(
    "first paint is the quaver (before the fetch settles)",
    h2_text(dom) === "quaver",
    h2_text(dom),
  );
  await sleep(0); // let the fetch settle
  tick();
  check("no puzzle today: the board stays the quaver", h2_text(dom) === "quaver", h2_text(dom));
  check("no date tag on the fallback", when_text(dom) === "", JSON.stringify(when_text(dom)));
  check(
    "the fallback tells no telemetry (no POST at all)",
    posts(dom).length === 0,
    JSON.stringify(posts(dom)),
  );
  check(
    "the fallback stores no attempt ('j-att' untouched)",
    stored_attempt(dom) === null,
    JSON.stringify(stored_attempt(dom)),
  );
  const get = gets(dom)[0];
  check(
    "the fetch asked for today in the visitor's own tz (minutes to ADD)",
    get && /^\/api\/puzzle\/today\?tz=-?\d+$/.test(get.url),
    get ? get.url : "no GET",
  );
  check(
    "the anonymous identity is created anyway (site-wide, Q16)",
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
      uuid_now(dom) || "",
    ),
    String(uuid_now(dom)),
  );
}

// ==== S8b · a fetched puzzle takes the board over ===========================
let daily_dom = null;
{
  const dom = boot_dom({ fetchMode: "ok", fetchBody: daily_json() });
  check(
    "the quaver paints first even with a puzzle waiting",
    h2_text(dom) === "quaver",
    h2_text(dom),
  );
  await sleep(0);
  tick();
  daily_dom = dom;
  check("the served puzzle's name is the title", h2_text(dom).startsWith(DAILY_NAME), h2_text(dom));
  check("the show date rides beside the name", when_text(dom).includes(DAILY_DATE), when_text(dom));
  check(
    "the dials sit where the served patches put them (90° · 50% · k +2)",
    row_val(dom, 0) === "90°" && row_val(dom, 1) === "50%" && row_val(dom, 2) === "k +2",
    [row_val(dom, 0), row_val(dom, 1), row_val(dom, 2)].join(" · "),
  );
  check(
    "the score is the core's match for the served start",
    score_val(dom) === puzzle.fmt1(shapes.match_pct(daily_shape, daily_initial())) + "%",
    score_val(dom),
  );
  check("a fresh attempt starts at zero", counter(dom) === "· 0 changes", JSON.stringify(counter(dom)));
  check("no POST at boot (nothing solved, nothing abandoned)", posts(dom).length === 0);
  const stored = stored_attempt(dom);
  check(
    "today's attempt is stored (date, zeroed counter, unsolved)",
    stored &&
      stored.date === DAILY_DATE &&
      stored.count === 0 &&
      stored.solved === false &&
      stored.reported === false &&
      stored.moves.length === 0,
    JSON.stringify(stored),
  );
  const s0 = Array.from(daily_initial())[0];
  check(
    "the stored dial state is the served start",
    stored &&
      JSON.stringify(stored.state[0]) ===
        JSON.stringify({ k: s0.k, r: s0.r, phase: s0.phase_deg }),
    JSON.stringify(stored && stored.state[0]) + " vs " + JSON.stringify({ k: s0.k, r: s0.r, phase: s0.phase_deg }),
  );
  check("the canvas repainted for the new shape", canvas_ops(dom).arc >= 5, "arcs " + canvas_ops(dom).arc);
}

// ==== S8c · resume: a stored attempt from today =============================
{
  const seed_state = Array.from(daily_initial());

  seed_state[0] = puzzle.step(DAILY_KINDS[0], seed_state[0], 1, daily_shape.dial_max_r);
  seed_state[0] = puzzle.step(DAILY_KINDS[0], seed_state[0], 1, daily_shape.dial_max_r);
  seed_state[0] = puzzle.step(DAILY_KINDS[0], seed_state[0], 1, daily_shape.dial_max_r);
  const dom = boot_dom({
    fetchMode: "ok",
    fetchBody: daily_json(),
    seed: {
      "j-att": attempt_json({
        date: DAILY_DATE,
        state: seed_state,
        moves: [
          [0, 1],
          [0, 1],
          [0, 1],
        ],
        count: 3,
      }),
    },
  });
  await sleep(0);
  tick();
  check(
    "the stored dials are restored (90° + 3 steps = 105°)",
    row_val(dom, 0) === "105°",
    row_val(dom, 0),
  );
  check("the stored counter is restored", counter(dom) === "· 3 changes", JSON.stringify(counter(dom)));
  check(
    "the restored score is the core's match for that state",
    score_val(dom) === puzzle.fmt1(shapes.match_pct(daily_shape, toList(seed_state))) + "%",
    score_val(dom),
  );
  check("resuming posts nothing", posts(dom).length === 0, JSON.stringify(posts(dom)));
  const stored = stored_attempt(dom);
  check(
    "the stored attempt is left alone (count 3, still unsolved)",
    stored && stored.count === 3 && stored.solved === false,
    JSON.stringify(stored),
  );
}

// ==== S8d · the solve moment posts ONCE =====================================
{
  const dom = daily_dom;
  const uuid = uuid_now(dom);
  for (const [slot, dir] of daily_walk.moves) {
    const btn = row_button(dom, slot, dir);
    if (!btn) break;
    btn.click();
    tick();
  }
  tick(34, 2);
  check(
    "the walk solves the board (badge shown)",
    dom.window.document.querySelector(".score.solved") !== null,
    "score " + score_val(dom),
  );
  const count = counter_n(dom);
  let solve_calls = posts(dom).filter((c) => c.url === "/api/solve");
  check("exactly one solve POST", solve_calls.length === 1, "got " + solve_calls.length);
  const body = solve_calls.length ? JSON.parse(solve_calls[0].body) : {};
  check(
    "the solve body carries the identity, the date and the moves played",
    body.uuid === uuid && body.puzzleDate === DAILY_DATE && Array.isArray(body.moves),
    JSON.stringify({ uuid: body.uuid === uuid, date: body.puzzleDate, moves: body.moves && body.moves.length }),
  );
  check(
    "the reported move list matches the frozen counter",
    body.moves && body.moves.length === count && body.moves[0].slot !== undefined && "dir" in body.moves[0],
    "moves " + (body.moves && body.moves.length) + " vs counter " + count,
  );
  // the solve POST is in flight: the record says solved-but-unreported until
  // the answer lands (a solve that never confirms is re-sent next boot)
  const inflight = stored_attempt(dom);
  check(
    "while the solve POST is in flight the attempt is stored unsent",
    inflight && inflight.solved === true && inflight.reported === false && inflight.count === count,
    JSON.stringify(inflight && { solved: inflight.solved, reported: inflight.reported, count: inflight.count }),
  );
  await sleep(0); // the stubbed POST settles on a microtask
  tick();
  const stored = stored_attempt(dom);
  check(
    "the confirmed solve is stored as solved + reported (nothing left to re-send)",
    stored && stored.solved === true && stored.reported === true && stored.count === count,
    JSON.stringify(stored && { solved: stored.solved, reported: stored.reported, count: stored.count }),
  );
  // further steps are free: the record is final and nothing is re-posted
  row_button(dom, 0, 1).click();
  tick(34, 2);
  solve_calls = posts(dom).filter((c) => c.url === "/api/solve");
  check("stepping after the solve re-posts nothing", solve_calls.length === 1, "got " + solve_calls.length);
  check(
    "and the counter stays frozen",
    counter_n(dom) === count,
    count + " → " + counter_n(dom),
  );
}

// ==== S8e · reset before a solve abandons the attempt =======================
{
  const dom = boot_dom({ fetchMode: "ok", fetchBody: daily_json() });
  await sleep(0);
  tick();
  const uuid = uuid_now(dom);
  for (let i = 0; i < 4; i++) {
    row_button(dom, 0, 1).click();
    tick();
  }
  check("four steps counted", counter(dom) === "· 4 changes", JSON.stringify(counter(dom)));
  check("no solve POST while unsolved", posts(dom).filter((c) => c.url === "/api/solve").length === 0);
  dom.window.document.querySelector("button.reset").click();
  tick(34, 2);
  const abandons = posts(dom).filter((c) => c.url === "/api/attempts/abandon");
  check("reset abandons the played attempt (one POST)", abandons.length === 1, "got " + abandons.length);
  const body = abandons.length ? JSON.parse(abandons[0].body) : {};
  check(
    "the abandon body carries the OLD count and today's date",
    body.uuid === uuid && body.puzzleDate === DAILY_DATE && body.moves === 4,
    JSON.stringify({ date: body.puzzleDate, moves: body.moves }),
  );
  check("the counter zeroes on reset", counter(dom) === "· 0 changes", JSON.stringify(counter(dom)));
  check("the dials go back to the served start", row_val(dom, 0) === "90°", row_val(dom, 0));
  const stored = stored_attempt(dom);
  check(
    "a fresh attempt replaces it (same date, count 0)",
    stored && stored.date === DAILY_DATE && stored.count === 0 && stored.moves.length === 0,
    JSON.stringify(stored && { date: stored.date, count: stored.count, moves: stored.moves.length }),
  );
  // resetting an untouched attempt is not an abandonment
  dom.window.document.querySelector("button.reset").click();
  tick(34, 2);
  check(
    "a reset with nothing played abandons nothing",
    posts(dom).filter((c) => c.url === "/api/attempts/abandon").length === 1,
    "got " + posts(dom).filter((c) => c.url === "/api/attempts/abandon").length,
  );
}

// ==== S8f · a new day retires yesterday's attempt ===========================
{
  const old_state = Array.from(daily_initial());
  for (let i = 0; i < 7; i++) {
    old_state[0] = puzzle.step(DAILY_KINDS[0], old_state[0], 1, daily_shape.dial_max_r);
  }
  const dom = boot_dom({
    fetchMode: "ok",
    fetchBody: daily_json(),
    seed: {
      "j-att": attempt_json({
        date: OLD_DATE,
        state: old_state,
        moves: Array.from({ length: 7 }, () => [0, 1]),
        count: 7,
      }),
    },
  });
  await sleep(0);
  tick();
  const abandons = posts(dom).filter((c) => c.url === "/api/attempts/abandon");
  check(
    "yesterday's unsolved attempt is abandoned when today opens",
    abandons.length === 1,
    "got " + abandons.length,
  );
  const body = abandons.length ? JSON.parse(abandons[0].body) : {};
  check(
    "the abandon names the OLD date and its 7 moves",
    body.puzzleDate === OLD_DATE && body.moves === 7,
    JSON.stringify({ date: body.puzzleDate, moves: body.moves }),
  );
  const stored = stored_attempt(dom);
  check(
    "today's attempt takes its place",
    stored && stored.date === DAILY_DATE && stored.count === 0,
    JSON.stringify(stored && { date: stored.date, count: stored.count }),
  );
  check(
    "the board shows today's start, not yesterday's dials",
    row_val(dom, 0) === "90°" && counter(dom) === "· 0 changes",
    row_val(dom, 0) + " · " + counter(dom),
  );
}

// ==== S8g · a solved day reloads solved — and re-reports only if it must ===
{
  const solved_state = daily_walk.state;
  const solved_count = daily_walk.moves.length;
  const dom = boot_dom({
    fetchMode: "ok",
    fetchBody: daily_json(),
    seed: {
      "j-att": attempt_json({
        date: DAILY_DATE,
        state: solved_state,
        moves: daily_walk.moves,
        count: solved_count,
        solved: true,
        reported: true,
      }),
    },
  });
  await sleep(0);
  tick();
  check(
    "the solved badge is restored on reload",
    dom.window.document.querySelector(".score.solved") !== null,
    "score " + score_val(dom),
  );
  check(
    "the solved-in number is restored",
    counter_n(dom) === solved_count,
    solved_count + " vs " + counter_n(dom),
  );
  check(
    "an already-reported solve posts nothing",
    posts(dom).length === 0,
    JSON.stringify(posts(dom)),
  );
  const stored = stored_attempt(dom);
  check(
    "the stored record survives the reload untouched",
    stored && stored.solved === true && stored.reported === true && stored.count === solved_count,
    JSON.stringify(stored && { solved: stored.solved, reported: stored.reported, count: stored.count }),
  );

  // a solve whose POST never landed is re-sent on the next boot (the backend's
  // solve REPLACES the row, so a duplicate costs nothing)
  const unsent = boot_dom({
    fetchMode: "ok",
    fetchBody: daily_json(),
    seed: {
      "j-att": attempt_json({
        date: DAILY_DATE,
        state: solved_state,
        moves: daily_walk.moves,
        count: solved_count,
        solved: true,
        reported: false,
      }),
    },
  });
  await sleep(0);
  tick();
  const resends = posts(unsent).filter((c) => c.url === "/api/solve");
  check("an unreported solve is re-sent exactly once", resends.length === 1, "got " + resends.length);
  const body = resends.length ? JSON.parse(resends[0].body) : {};
  check(
    "the re-sent solve carries the stored moves and date",
    body.puzzleDate === DAILY_DATE && body.moves && body.moves.length === solved_count,
    JSON.stringify({ date: body.puzzleDate, moves: body.moves && body.moves.length }),
  );
  const after = stored_attempt(unsent);
  check("the re-send marks the attempt reported", after && after.reported === true, JSON.stringify(after && after.reported));
}

// ==== S8h · network trouble is the fallback, not an error ===================
{
  for (const [label, opts] of [
    ["a rejected request (offline)", { fetchMode: "reject" }],
    ["a 500 from the API", { fetchMode: "http500" }],
    ["a document this decoder cannot use", { fetchMode: "ok", fetchBody: "<html>tunnel</html>" }],
  ]) {
    const dom = boot_dom(opts);
    await sleep(0);
    tick();
    check(
      label + ": the quaver stays, nothing is posted",
      h2_text(dom) === "quaver" && posts(dom).length === 0,
      h2_text(dom) + " / posts " + posts(dom).length,
    );
  }
  // a POST that fails changes nothing visible: the attempt stays unreported
  const dom = boot_dom({ fetchMode: "ok", fetchBody: daily_json(), postFails: true });
  await sleep(0);
  tick();
  for (const [slot, dir] of daily_walk.moves) {
    const btn = row_button(dom, slot, dir);
    if (!btn) break;
    btn.click();
    tick();
  }
  tick(34, 2);
  const stored = stored_attempt(dom);
  check(
    "an unsent solve is stored as solved-but-unreported (the next boot retries)",
    stored && stored.solved === true && stored.reported === false,
    JSON.stringify(stored && { solved: stored.solved, reported: stored.reported }),
  );
  check(
    "the badge still shows (the player solved it, whatever the network did)",
    dom.window.document.querySelector(".score.solved") !== null,
  );
}

console.log("");
console.log(passed + "/" + (passed + failed) + " checks passed");
if (failed > 0) process.exit(1);