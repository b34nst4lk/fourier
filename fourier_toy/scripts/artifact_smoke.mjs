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
    "viewport stays user-scalable (pinch-zoom accessibility preserved)",
    !/user-scalable\s*=\s*no/i.test(html) && !/maximum-scale\s*=\s*1\b/i.test(html),
    "viewport meta limits zoom",
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
  check(
    "bar: unboxed score (b), compact icon chip",
    dom.window.document.querySelector(".score b") !== null &&
      themeBtn.getAttribute("aria-label") === "dark mode" &&
      themeBtn.querySelector("svg.icon") !== null,
    "aria: " + themeBtn.getAttribute("aria-label"),
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
  check(
    "score tracks the stepped state",
    score_val(dom) === puzzle.fmt1(match_of(state)) + "%",
    "dom " + score_val(dom) + " vs core " + puzzle.fmt1(match_of(state)) + "%",
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
}

// ==== S3 · dial-home solve path ==============================================
console.log("S3 · dial-home solve path — every dialable at (or nearest to) truth ⇒ solved");
{
  const truth = Array.from(shape.dial);
  const t0 = truth[0], t1 = truth[1], t2 = truth[2];
  // slot 0: phase 0° → truth via the shortest direction around the dial
  const up = ((t0.phase_deg - 0 + 360) % 360) / 5;
  const down = ((0 - t0.phase_deg + 360) % 360) / 5;
  const dir = up <= down ? 1 : -1;
  for (let i = 0; i < Math.min(up, down); i++) {
    row_button(dom, 0, dir).click();
    state = step_slot(state, 0, dir);
    tick();
  }
  // slot 1: radius 0% → nearest reachable step to truth (unit = 2% of max)
  const unit = 0.02 * shape.dial_max_r;
  const r_up = Math.round((t1.r - 0) / unit);
  for (let i = 0; i < r_up; i++) {
    row_button(dom, 1, 1).click();
    state = step_slot(state, 1, 1);
    tick();
  }
  // slot 2: k −5 → truth k
  const k_clicks = Math.abs(t2.k - -5);
  const k_dir = t2.k > -5 ? 1 : -1;
  for (let i = 0; i < k_clicks; i++) {
    row_button(dom, 2, k_dir).click();
    state = step_slot(state, 2, k_dir);
    tick();
  }
  tick(34, 3);
  check(
    "score matches the core at the stepped state",
    score_val(dom) === puzzle.fmt1(match_of(state)) + "%",
    "dom " + score_val(dom) + " vs core " + puzzle.fmt1(match_of(state)) + "%",
  );
  const solved = dom.window.document.querySelector(".score.solved");
  check("solved badge appears at ≥ 95%", solved !== null, "score " + score_val(dom));
}

// ==== S4 · reset ===============================================================
console.log("S4 · reset returns to the initial state");
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
  check("reset clears the solved badge", !dom.window.document.querySelector(".score.solved"));
}

// ==== S5 · theme toggle ========================================================
console.log("S5 · theme toggle mirrors onto the body");
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

// ==== S6 · hold-to-repeat on the steppers ======================================
console.log("S6 · hold-to-repeat — auto-steps while held, tap steps once");
{
  const fire = (name, el) =>
    el.dispatchEvent(new dom.window.Event(name, { bubbles: true }));

  const v0 = parseInt(row_val(dom, 0), 10);
  const btn = row_button(dom, 0, -1);
  fire("pointerdown", btn);
  await sleep(700);
  fire("pointerup", btn);
  tick(); // flush the RAF-pending renders the repeats scheduled
  const v1 = parseInt(row_val(dom, 0), 10);
  const n = (v0 - v1) / 5;
  check("hold auto-repeats the stepper (≥ 2 steps in 700ms)", n >= 2, v0 + "° → " + v1 + "° (n=" + n + ")");
  for (let i = 0; i < n; i++) state = step_slot(state, 0, -1);
  check(
    "score matches the core after n repeat steps",
    score_val(dom) === puzzle.fmt1(match_of(state)) + "%",
    "dom " + score_val(dom) + " vs core " + puzzle.fmt1(match_of(state)) + "%",
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
    parseInt(row_val(dom, 0), 10) === v1 - 5 &&
      score_val(dom) === puzzle.fmt1(match_of(state)) + "%",
    row_val(dom, 0) + " vs " + (v1 - 5) + "°, score " + score_val(dom),
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