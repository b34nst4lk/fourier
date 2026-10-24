// App-level smoke for the single-file dist artifact: loads dist/index.html
// into jsdom, evals the EXACT shipped bundle (jsdom can't run type="module"
// scripts, but the esbuild bundle is self-contained with no import/export
// syntax, so it evaluates identically as a classic script), and drives the
// real Lustre runtime end to end: cold-load boot, routing, dialing, solve
// badge, reset, theme, fixed-slot hiding, wrap/floor behavior.
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

function boot_dom(hash = "") {
  raf_q = [];
  NOW = 1000.0;
  const dom = new JSDOM(html, {
    url: "https://toy.test/" + hash,
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
function setup_of(id) {
  const s = puzzle.find(id)[0];
  if (!s || !s.patches) throw new Error("no setup " + id);
  return s;
}
const initial_state = (setup) =>
  puzzle.initial(puzzle.shape_of(setup.shape), setup.patches);
function step_slot(shape, setup, state, slot, dir) {
  const kinds = Array.from(setup.dials);
  // mirror update(): index-wise step, rebuilt as a real Gleam cons list
  return toList(
    Array.from(state, (s, i) =>
      i === slot ? puzzle.step(kinds[i], s, dir, shape.dial_max_r) : s,
    ),
  );
}
const match_of = (shape, state) => shapes.match_pct(shape, state);

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
function score_text(dom) {
  const el = dom.window.document.querySelector(".score");
  return el ? text(el).replace(/\s+/g, " ") : null;
}
function score_val(dom) {
  const el = dom.window.document.querySelector(".score b");
  return el ? text(el) : null;
}
function rows(dom) {
  return [...dom.window.document.querySelectorAll(".rows .row")];
}
function row_button(dom, slot, dir) {
  // rendered rows skip fixed slots — map slot → rendered row
  const setup_kinds = dom.__setup_kinds;
  const rendered = setup_kinds
    .map((k, i) => (k !== null && "" + k !== "DialFixed" ? i : null))
    .filter((i) => i !== null);
  const r = rows(dom)[rendered.indexOf(slot)];
  if (!r) return null;
  const btns = r.querySelectorAll("button.btn");
  return dir < 0 ? btns[0] : btns[1];
}
async function go(dom, hash) {
  dom.window.location.hash = hash;
  await sleep(20); // let jsdom fire hashchange
  tick();
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

// ==== S1 · cold load straight onto a board (init effects run pre-render) =====
console.log("S1 · cold load at #p6 — pre-mount sync payload must paint after boot");
const p6 = setup_of("p6");
let dom = boot_dom("#p6");
dom.__setup_kinds = Array.from(p6.dials).map((k) => k.constructor.name);
tick(); // boot retry binds the canvas, pump queues the frame
tick(34, 5); // draw frames
{
  const ops = canvas_ops(dom);
  check("canvas booted and painted (arcs ≥ 5: 4 circles + pen)", ops && ops.arc >= 5, "arcs " + (ops && ops.arc));
  check("no NaN coordinates", ops && ops.nan === 0, "nan " + (ops && ops.nan));
  check(
    "backing store sized (600 = 300css × dpr2)",
    board_canvas(dom).width === 600,
    String(board_canvas(dom).width),
  );
  const expect = puzzle.fmt1(match_of(puzzle.shape_of("star"), initial_state(p6)));
  check(
    "score shows the core-computed initial match",
    score_val(dom) === expect + "%",
    "dom " + score_val(dom) + " vs core " + expect + "%",
  );
  check("fixed slot 4 hidden (3 rows)", rows(dom).length === 3, "rows " + rows(dom).length);
  check(
    "top bar matches the prototype: unboxed score (b), compact night chip",
    dom.window.document.querySelector(".score b") !== null &&
      dom.window.document.querySelector(".score .val") === null &&
      text(dom.window.document.querySelector("button.theme")) === "night",
    "score b: " + (dom.window.document.querySelector(".score b") !== null) +
      ", theme: " + text(dom.window.document.querySelector("button.theme")),
  );
}

// ==== S2 · dials: wrap, step, disable ========================================
console.log("S2 · dial behavior — wrap, ground-truth steps, floor disable");
{
  const shape = puzzle.shape_of("star");
  let state = initial_state(p6);
  // phase wrap: 0° − 5° → 355°
  row_button(dom, 0, -1).click();
  state = step_slot(shape, p6, state, 0, -1);
  tick();
  const wrap_val = text(rows(dom)[0].querySelector(".val"));
  check("phase wraps below zero (355°)", wrap_val === "355°", wrap_val);
  check(
    "score tracks the stepped state",
    score_val(dom) === puzzle.fmt1(match_of(shape, state)) + "%",
    "dom " + score_val(dom) + " vs core " + puzzle.fmt1(match_of(shape, state)) + "%",
  );
  // radius floor: step slot 1 down to 0% — the minus button must disable
  let clicks = 0;
  let btn = row_button(dom, 1, -1);
  while (!btn.disabled && clicks < 200) {
    btn.click();
    state = step_slot(shape, p6, state, 1, -1);
    clicks++;
    tick();
    btn = row_button(dom, 1, -1);
  }
  check(
    "radius floors at 0% and disables minus",
    text(rows(dom)[1].querySelector(".val")) === "0%" && btn.disabled,
    text(rows(dom)[1].querySelector(".val")) + " disabled=" + btn.disabled,
  );
}

// ==== S3 · solve path on the star ============================================
console.log("S3 · dial-home solve path — every dialable at truth ⇒ solved badge");
{
  const shape = puzzle.shape_of("star");
  const truth = shape.dial; // cons list of TermState truth
  const t = Array.from(truth);
  // slot 0: phase to truth; slot 1: radius to truth; slot 2: k to truth
  const s0 = t[0], s1 = t[1], s2 = t[2];
  // slot 0: phase 355° → truth via the shortest direction around the dial
  const up = ((s0.phase_deg - 355 + 360) % 360) / 5;
  const down = ((355 - s0.phase_deg + 360) % 360) / 5;
  const dir = up <= down ? 1 : -1;
  for (let i = 0; i < Math.min(up, down); i++) {
    row_button(dom, 0, dir).click();
    tick();
  }
  const r_unit = 0.02 * shape.dial_max_r;
  const r_up = Math.round((s1.r - 0) / r_unit); // from 0% back to truth
  for (let i = 0; i < r_up; i++) {
    row_button(dom, 1, 1).click();
    tick();
  }
  const k_down = 8 - s2.k; // from KSet(8) down to truth k
  for (let i = 0; i < k_down; i++) {
    row_button(dom, 2, -1).click();
    tick();
  }
  tick(34, 3);
  const solved = dom.window.document.querySelector(".score.solved");
  check("solved badge appears at ≥ 95%", solved !== null, score_text(dom));
  check(
    "star tops out at the truncation bound (≈97.7%)",
    score_val(dom) === puzzle.fmt1(match_of(shape, truth)) + "%",
    "dom " + score_val(dom) + " vs core " + puzzle.fmt1(match_of(shape, truth)) + "%",
  );
}

// ==== S4 · reset =============================================================
console.log("S4 · reset returns to the initial state");
{
  dom.window.document.querySelector("button.reset").click();
  tick(34, 2);
  const expect = puzzle.fmt1(match_of(puzzle.shape_of("star"), initial_state(p6)));
  check(
    "reset restores the initial match",
    score_val(dom) === expect + "%",
    "dom " + score_val(dom) + " vs core " + expect + "%",
  );
  check("reset clears the solved badge", !dom.window.document.querySelector(".score.solved"));
}

// ==== S5 · theme toggle ======================================================
console.log("S5 · theme toggle mirrors onto the body");
{
  dom.window.document.querySelector("button.theme").click();
  tick();
  check("body flips to dark", dom.window.document.body.getAttribute("data-theme") === "dark");
  check(
    "chip label flips to day",
    text(dom.window.document.querySelector("button.theme")) === "day",
  );
  dom.window.document.querySelector("button.theme").click();
  tick();
  check("body flips back to light", dom.window.document.body.getAttribute("data-theme") === "light");
}

// ==== S6 · home → board navigation (stash path) ===============================
console.log("S6 · home → p8 fish — payload stashed while unmounted paints after mount");
{
  await go(dom, "#"); // back link → home
  tick();
  const cards = dom.window.document.querySelectorAll("a.card");
  check("home shows the 5 experiment cards", cards.length === 5, "cards " + cards.length);
  check("no canvas on home", board_canvas(dom) === null);

  await go(dom, "#p8");
  tick(); // retry binds, pump queues the frame
  tick(34, 4);
  const p8 = setup_of("p8");
  dom.__setup_kinds = Array.from(p8.dials).map((k) => k.constructor.name);
  const ops = canvas_ops(dom);
  check(
    "fish board painted after navigation (stash survived the unmounted window)",
    ops && ops.arc >= 5 && ops.nan === 0,
    "arcs " + (ops && ops.arc) + ", nan " + (ops && ops.nan),
  );
  const expect = puzzle.fmt1(match_of(puzzle.shape_of("fish"), initial_state(p8)));
  check(
    "fish score is the core-computed initial match",
    score_val(dom) === expect + "%",
    "dom " + score_val(dom) + " vs core " + expect + "%",
  );
  check("fish fixed slot hidden (3 rows)", rows(dom).length === 3, "rows " + rows(dom).length);
}

// ==== S7 · board → board (direct hashchange) =================================
console.log("S7 · p8 → #p10 — board-to-board keeps painting");
{
  const before_el = board_canvas(dom);
  const before_arcs = canvas_ops(dom).arc; // snapshot NUMBER — ops is a live object
  await go(dom, "#p10");
  tick(34, 4);
  const after_el = board_canvas(dom);
  const after_ops = canvas_ops(dom);
  check(
    "reconciler preserves the canvas element across board swaps",
    after_el === before_el,
    after_el === before_el ? "same element" : "replaced — rebind path applies",
  );
  const p10 = setup_of("p10");
  dom.__setup_kinds = Array.from(p10.dials).map((k) => k.constructor.name);
  const expect = puzzle.fmt1(match_of(puzzle.shape_of("flower"), initial_state(p10)));
  check(
    "p10 score is the core-computed initial match",
    score_val(dom) === expect + "%",
    "dom " + score_val(dom) + " vs core " + expect + "%",
  );
  check(
    "p10 board painted (ops grew through the swap)",
    after_ops && after_ops.arc >= before_arcs + 5,
    "arcs " + before_arcs + " → " + (after_ops && after_ops.arc),
  );
  check("p10 shows all four rows (no fixed slot)", rows(dom).length === 4, "rows " + rows(dom).length);
}

console.log("");
console.log(passed + "/" + (passed + failed) + " checks passed");
if (failed > 0) process.exit(1);